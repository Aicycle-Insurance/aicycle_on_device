import Foundation
import UIKit

/// Uploads queued photos. Policy is shared with the Dart queue
/// (`photo_upload_queue.dart`) and the Android worker; the queue file's
/// top-level `mode` selects it:
///  - `background`: user is still capturing; 30s idle / 90s total, long backoff.
///  - `fast`: user is waiting on the upload screen; 15s idle / 60s total,
///    quick retries.
///
/// While the app is in the foreground every upload runs on a default
/// URLSession so the timeouts above really apply and failures are reported.
/// A background URLSession silently waits and retries when it cannot connect,
/// so it is only used while the app is in the background; tasks are moved
/// between the two when the app changes state.
final class AICycleBackgroundUploader: NSObject, URLSessionDelegate, URLSessionTaskDelegate,
  URLSessionDataDelegate, @unchecked Sendable
{
  static let shared = AICycleBackgroundUploader()

  private static let fastMode = "fast"

  /// From this many seconds into sending a body, an upload whose measured
  /// speed cannot finish within the total timeout is cut early.
  private static let speedCheckAfter: TimeInterval = 15

  private let identifier = "com.aicycle.yolo.background-upload"
  private let ioQueue = DispatchQueue(label: "com.aicycle.yolo.background-upload.io", qos: .utility)
  private let queueFileLock = NSLock()
  private let responseDataLock = NSLock()
  private let stateLock = NSLock()
  private var backgroundCompletionHandler: (() -> Void)?
  private var responseDataByTaskKey: [String: Data] = [:]

  /// Bumped by cancel/retry-now/app state changes so that delayed retries
  /// scheduled before them are dropped instead of creating duplicate tasks.
  private var generation = 0
  private var appInForeground = true
  private var lastQueueFilePath: String?
  /// When each foreground upload started sending its body (speed check).
  private var sendStartByTaskKey: [String: Date] = [:]
  /// Uploads cancelled by the speed check; completed as timeouts.
  private var tooSlowTaskKeys: Set<String> = []

  private lazy var backgroundSession: URLSession = {
    let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.httpMaximumConnectionsPerHost = 2
    configuration.timeoutIntervalForRequest = 30
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }()

  /// Foreground, user still capturing.
  private lazy var captureSession = makeForegroundSession(idle: 30, total: 90)

  /// Foreground, user waiting on the upload screen.
  private lazy var fastSession = makeForegroundSession(idle: 15, total: 60)

  private var foregroundSessions: [URLSession] { [captureSession, fastSession] }
  private var allSessions: [URLSession] { [backgroundSession, captureSession, fastSession] }

  private func makeForegroundSession(idle: TimeInterval, total: TimeInterval) -> URLSession {
    let configuration = URLSessionConfiguration.default
    configuration.httpMaximumConnectionsPerHost = 2
    // URLSession has no separate connect timeout: `idle` covers connecting,
    // sending and waiting for the response whenever no byte moves.
    configuration.timeoutIntervalForRequest = idle
    configuration.timeoutIntervalForResource = total
    configuration.waitsForConnectivity = false
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }

  private override init() {
    super.init()
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(appDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    center.addObserver(
      self, selector: #selector(appWillEnterForeground),
      name: UIApplication.willEnterForegroundNotification, object: nil)
    let readState: () -> Void = { [weak self] in
      self?.setAppInForeground(UIApplication.shared.applicationState != .background)
    }
    if Thread.isMainThread { readState() } else { DispatchQueue.main.async(execute: readState) }
  }

  // MARK: - Public API

  func scheduleUpload(_ item: [String: Any], completion: ((Error?) -> Void)? = nil) {
    guard let id = item["id"] as? String else {
      completion?(UploadError.badArguments("Missing id"))
      return
    }
    if let queueFilePath = item["queueFilePath"] as? String {
      rememberQueueFilePath(queueFilePath)
    }

    allTasks { [weak self] tasks in
      guard let self else { return }
      if tasks.contains(where: { self.isActive($0) && self.taskMatches($0, id: id) }) {
        completion?(nil)
        return
      }

      self.ioQueue.async {
        do {
          let task = try self.makeUploadTask(for: item, fast: self.isFast(item))
          task.resume()
          NSLog("AICycleBackgroundUploader: scheduled upload id=%@", id)
          completion?(nil)
        } catch {
          completion?(error)
        }
      }
    }
  }

  /// "Thử lại": drops tasks still waiting on backoff (no bytes sent yet) so
  /// Dart can reschedule them immediately. In-flight uploads keep running.
  func retryNow(completion: @escaping () -> Void) {
    bumpGeneration()
    allTasks { [weak self] tasks in
      guard let self else { return }
      for task in tasks where self.isActive(task) && task.countOfBytesSent == 0 {
        task.cancel()
      }
      completion()
    }
  }

  /// Cancels every upload, including in-flight ones.
  func cancelAll(completion: @escaping () -> Void) {
    bumpGeneration()
    allTasks { tasks in
      tasks.forEach { $0.cancel() }
      NSLog("AICycleBackgroundUploader: cancelled %d upload tasks", tasks.count)
      completion()
    }
  }

  func handleEvents(for identifier: String, completionHandler: @escaping () -> Void) {
    guard identifier == self.identifier else {
      completionHandler()
      return
    }
    backgroundCompletionHandler = completionHandler
    _ = backgroundSession
  }

  // MARK: - App state

  /// Foreground uploads stop when the app is suspended: hand everything to
  /// the background session so iOS keeps uploading for us.
  @objc private func appDidEnterBackground() {
    setAppInForeground(false)
    bumpGeneration()
    var backgroundTask = UIBackgroundTaskIdentifier.invalid
    let endBackgroundTask = {
      guard backgroundTask != .invalid else { return }
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
    backgroundTask = UIApplication.shared.beginBackgroundTask(
      withName: "AICycleUploadHandOff", expirationHandler: endBackgroundTask)
    moveQueue(cancelling: foregroundSessions, keepStarted: false) {
      DispatchQueue.main.async(execute: endBackgroundTask)
    }
  }

  /// Back in the foreground: uploads that have not started yet move to the
  /// foreground sessions so timeouts apply and failures are reported again.
  /// Uploads already sending keep going in the background session.
  @objc private func appWillEnterForeground() {
    setAppInForeground(true)
    bumpGeneration()
    moveQueue(cancelling: [backgroundSession], keepStarted: true) {}
  }

  /// Cancels the active tasks of [sessions] (except ones already sending when
  /// [keepStarted]) and re-creates every pending queue item that has no
  /// active task left, on the session matching the current app state.
  private func moveQueue(
    cancelling sessions: [URLSession],
    keepStarted: Bool,
    completion: @escaping () -> Void
  ) {
    tasks(of: sessions) { [weak self] tasks in
      guard let self else { return completion() }
      for task in tasks where self.isActive(task) {
        if keepStarted && task.countOfBytesSent > 0 { continue }
        task.cancel()
      }
      self.scheduleQueuedItems(fallbackQueueFilePath: tasks.lazy.compactMap {
        self.decodeDescription($0)?["queueFilePath"] as? String
      }.first, completion: completion)
    }
  }

  /// Schedules every pending queue item that has no active task. Items still
  /// in backoff start when due (foreground) or with an earliest begin date
  /// (background).
  private func scheduleQueuedItems(
    fallbackQueueFilePath: String?,
    completion: @escaping () -> Void
  ) {
    guard let queueFilePath = currentQueueFilePath() ?? fallbackQueueFilePath else {
      return completion()
    }
    let queue = readQueueMeta(queueFilePath: queueFilePath)
    if queue["paused"] as? Bool ?? false { return completion() }
    let fast = (queue["mode"] as? String) == Self.fastMode
    let items = queue["items"] as? [[String: Any]] ?? []
    allTasks { [weak self] tasks in
      guard let self else { return completion() }
      let activeIds = Set(
        tasks.filter(self.isActive).compactMap { self.decodeDescription($0)?["id"] as? String })
      let generation = self.currentGeneration()
      var scheduled = 0
      for item in items {
        guard let id = item["id"] as? String, !activeIds.contains(id),
          !["succeeded", "skipped", "rejected"].contains(item["status"] as? String ?? "pending"),
          let filePath = item["filePath"] as? String,
          FileManager.default.fileExists(atPath: filePath)
        else { continue }
        var platformItem = item
        platformItem["queueFilePath"] = queueFilePath
        platformItem["mode"] = fast ? Self.fastMode : "background"
        self.startUpload(platformItem, fast: fast, generation: generation)
        scheduled += 1
      }
      NSLog(
        "AICycleBackgroundUploader: moved %d uploads to %@ session", scheduled,
        self.isAppInForeground() ? "foreground" : "background")
      completion()
    }
  }

  /// Creates and starts the upload for [item] once it is due. Foreground
  /// sessions have no earliest-begin date, so backoff is waited here.
  private func startUpload(_ item: [String: Any], fast: Bool, generation: Int) {
    let nextAttemptAt = item["nextAttemptAtMillis"] as? Int ?? 0
    let delay = isAppInForeground() ? max(0, Double(nextAttemptAt - nowMillis()) / 1000) : 0
    ioQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
      guard let self else { return }
      // Cancel / retry-now / app state change happened meanwhile; whoever
      // triggered it reschedules what is left.
      guard self.currentGeneration() == generation else { return }
      // Paused: Dart reschedules everything on resume.
      guard !self.isPaused(queueFilePath: item["queueFilePath"] as? String) else { return }
      do {
        try self.makeUploadTask(for: item, fast: fast).resume()
      } catch {
        NSLog(
          "AICycleBackgroundUploader: failed to start upload id=%@ error=%@",
          item["id"] as? String ?? "", error.localizedDescription)
      }
    }
  }

  // MARK: - Task creation

  private func makeUploadTask(for item: [String: Any], fast: Bool) throws -> URLSessionUploadTask {
    guard let urlString = item["url"] as? String,
      let url = URL(string: urlString),
      let filePath = item["filePath"] as? String
    else {
      throw UploadError.badArguments("Missing url or filePath")
    }

    let imageURL = URL(fileURLWithPath: filePath)
    guard FileManager.default.fileExists(atPath: imageURL.path) else {
      NSLog("AICycleBackgroundUploader: file missing id=%@", item["id"] as? String ?? "")
      throw UploadError.fileMissing
    }

    let boundary = "aicycle-\(UUID().uuidString)"
    let bodyURL = imageURL.deletingPathExtension()
      .appendingPathExtension("\(UUID().uuidString).multipart")
    try writeMultipartBody(item: item, imageURL: imageURL, bodyURL: bodyURL, boundary: boundary)

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    if let headers = item["headers"] as? [String: String] {
      for (key, value) in headers {
        request.setValue(value, forHTTPHeaderField: key)
      }
    }

    var description = item
    description["bodyPath"] = bodyURL.path
    let foreground = isAppInForeground()
    let session = foreground ? (fast ? fastSession : captureSession) : backgroundSession
    let task = session.uploadTask(with: request, fromFile: bodyURL)
    task.taskDescription = encodeDescription(description)
    // Captured photos first; context-stream frames must not hold them back.
    task.priority =
      item["isCallEngine"] as? Bool == true
      ? URLSessionTask.highPriority : URLSessionTask.lowPriority
    if !foreground, let nextAttemptAt = item["nextAttemptAtMillis"] as? Int,
      nextAttemptAt > nowMillis()
    {
      task.earliestBeginDate = Date(timeIntervalSince1970: Double(nextAttemptAt) / 1000)
    }
    return task
  }

  private func writeMultipartBody(
    item: [String: Any],
    imageURL: URL,
    bodyURL: URL,
    boundary: String
  ) throws {
    FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
    let out = try FileHandle(forWritingTo: bodyURL)
    defer { try? out.close() }

    if let fields = item["fields"] as? [String: String] {
      for (key, value) in fields {
        try out.writeAll("--\(boundary)\r\n")
        try out.writeAll("Content-Disposition: form-data; name=\"\(escape(key))\"\r\n\r\n")
        try out.writeAll("\(value)\r\n")
      }
    }

    let field = item["fileField"] as? String ?? "img"
    let fileName = item["fileName"] as? String ?? imageURL.lastPathComponent
    try out.writeAll("--\(boundary)\r\n")
    try out.writeAll(
      "Content-Disposition: form-data; name=\"\(escape(field))\"; filename=\"\(escape(fileName))\"\r\n"
    )
    try out.writeAll("Content-Type: image/jpeg\r\n\r\n")

    let input = try FileHandle(forReadingFrom: imageURL)
    defer { try? input.close() }
    while true {
      let chunk = input.readData(ofLength: 1024 * 1024)
      if chunk.isEmpty { break }
      out.write(chunk)
    }

    try out.writeAll("\r\n--\(boundary)--\r\n")
  }

  // MARK: - Helpers

  private func allTasks(_ completion: @escaping ([URLSessionTask]) -> Void) {
    tasks(of: allSessions, completion)
  }

  private func tasks(of sessions: [URLSession], _ completion: @escaping ([URLSessionTask]) -> Void) {
    let group = DispatchGroup()
    let lock = NSLock()
    var result: [URLSessionTask] = []
    for session in sessions {
      group.enter()
      session.getAllTasks { tasks in
        lock.lock()
        result.append(contentsOf: tasks)
        lock.unlock()
        group.leave()
      }
    }
    group.notify(queue: ioQueue) { completion(result) }
  }

  private func isActive(_ task: URLSessionTask) -> Bool {
    task.state == .running || task.state == .suspended
  }

  private func isFast(_ item: [String: Any]) -> Bool {
    (item["mode"] as? String) == Self.fastMode
  }

  private func bumpGeneration() {
    stateLock.lock()
    generation += 1
    stateLock.unlock()
  }

  private func currentGeneration() -> Int {
    stateLock.lock()
    defer { stateLock.unlock() }
    return generation
  }

  private func setAppInForeground(_ foreground: Bool) {
    stateLock.lock()
    appInForeground = foreground
    stateLock.unlock()
  }

  private func isAppInForeground() -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return appInForeground
  }

  private func rememberQueueFilePath(_ path: String) {
    stateLock.lock()
    lastQueueFilePath = path
    stateLock.unlock()
  }

  private func currentQueueFilePath() -> String? {
    stateLock.lock()
    defer { stateLock.unlock() }
    return lastQueueFilePath
  }

  private func taskMatches(_ task: URLSessionTask, id: String) -> Bool {
    decodeDescription(task)?["id"] as? String == id
  }

  private func encodeDescription(_ item: [String: Any]) -> String? {
    guard JSONSerialization.isValidJSONObject(item),
      let data = try? JSONSerialization.data(withJSONObject: item),
      let string = String(data: data, encoding: .utf8)
    else {
      return nil
    }
    return string
  }

  private func decodeDescription(_ task: URLSessionTask) -> [String: Any]? {
    guard let description = task.taskDescription,
      let data = description.data(using: .utf8)
    else {
      return nil
    }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  }

  private static func isRetryableHttp(_ code: Int) -> Bool {
    code == 408 || code == 429 || (500..<600).contains(code)
  }

  private static func retryDelay(fast: Bool, attempt: Int) -> TimeInterval {
    if fast {
      switch attempt {
      case ...1: return 0
      case 2: return 2
      default: return 5
      }
    }
    // Retry soon first so a brief network blip heals before the capture
    // screen's warning threshold, then back off up to 5 minutes.
    let delays: [TimeInterval] = [5, 15, 30, 60, 120, 300]
    return delays[min(max(attempt - 1, 0), delays.count - 1)]
  }

  private func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "\"", with: "\\\"")
  }

  private func nowMillis() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
  }

  private func taskKey(_ session: URLSession, _ task: URLSessionTask) -> String {
    let tag = session === fastSession ? "f" : session === captureSession ? "c" : "b"
    return "\(tag)-\(task.taskIdentifier)"
  }

  private func takeResponseBody(_ session: URLSession, _ task: URLSessionTask) -> String {
    responseDataLock.lock()
    let data = responseDataByTaskKey.removeValue(forKey: taskKey(session, task)) ?? Data()
    responseDataLock.unlock()
    return String(data: data, encoding: .utf8) ?? ""
  }

  // MARK: - Queue file

  private func readQueueMeta(queueFilePath: String?) -> [String: Any] {
    guard let queueFilePath,
      let data = try? Data(contentsOf: URL(fileURLWithPath: queueFilePath)),
      let queue = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }
    return queue
  }

  private func readMode(queueFilePath: String?) -> String {
    readQueueMeta(queueFilePath: queueFilePath)["mode"] as? String ?? "background"
  }

  /// Dart pauses the queue while an upload error is shown; nothing is sent
  /// until the user taps "Thử lại" / "Chụp tiếp".
  private func isPaused(queueFilePath: String?) -> Bool {
    readQueueMeta(queueFilePath: queueFilePath)["paused"] as? Bool ?? false
  }

  /// HTTP 400 whose body carries an `errorCodeFromEngine` listed in the queue
  /// file's `retryableEngineErrorCodes` (declared in Dart): the server stored
  /// the photo but its AI engine failed transiently, so retry like a 5xx.
  private func isRetryableEngineError(
    queueFilePath: String?,
    statusCode: Int,
    responseBody: String
  ) -> Bool {
    guard statusCode == 400 else { return false }
    let codes = readQueueMeta(queueFilePath: queueFilePath)["retryableEngineErrorCodes"] as? [Any]
    let retryable = Set((codes ?? []).compactMap(Self.engineCodeString))
    guard !retryable.isEmpty,
      let data = responseBody.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else {
      return false
    }
    return Self.findEngineErrorCodes(json).contains(where: retryable.contains)
  }

  /// Every `errorCodeFromEngine` value at any depth, as strings ("10012").
  private static func findEngineErrorCodes(_ node: Any) -> [String] {
    if let object = node as? [String: Any] {
      return object.flatMap { key, value -> [String] in
        if key == "errorCodeFromEngine" {
          return engineCodeString(value).map { [$0] } ?? []
        }
        return findEngineErrorCodes(value)
      }
    }
    if let array = node as? [Any] {
      return array.flatMap(findEngineErrorCodes)
    }
    return []
  }

  private static func engineCodeString(_ value: Any) -> String? {
    if let string = value as? String {
      let trimmed = string.trimmingCharacters(in: .whitespaces)
      return trimmed.isEmpty ? nil : trimmed
    }
    if let number = value as? NSNumber {
      return String(number.int64Value)
    }
    return nil
  }

  private func setResponseBody(_ item: inout [String: Any], _ responseBody: String) {
    if responseBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      item.removeValue(forKey: "responseBody")
    } else {
      item["responseBody"] = responseBody
    }
  }

  private func markSucceeded(
    queueFilePath: String?,
    id: String?,
    statusCode: Int,
    responseBody: String
  ) {
    updateQueue(queueFilePath: queueFilePath, id: id) { queue, item in
      let now = nowMillis()
      item["status"] = "succeeded"
      item["updatedAtMillis"] = now
      item["responseStatusCode"] = statusCode
      setResponseBody(&item, responseBody)
      item.removeValue(forKey: "lastError")
      item.removeValue(forKey: "errorType")
      queue["lastResponseAtMillis"] = now
      if item["isCallEngine"] as? Bool == true {
        queue["lastSuccessAtMillis"] = now
        queue.removeValue(forKey: "failureStreak")
      }
    }
  }

  private func markRejected(
    queueFilePath: String?,
    id: String?,
    statusCode: Int,
    responseBody: String
  ) {
    updateQueue(queueFilePath: queueFilePath, id: id) { queue, item in
      item["status"] = "rejected"
      item["updatedAtMillis"] = nowMillis()
      queue["lastResponseAtMillis"] = nowMillis()
      item["responseStatusCode"] = statusCode
      item["errorType"] = "rejected"
      setResponseBody(&item, responseBody)
      // The server answered, so it is reachable: the failure streak is over.
      if item["isCallEngine"] as? Bool == true {
        queue.removeValue(forKey: "failureStreak")
      }
    }
  }

  /// Returns the item's new attempt number and next due time.
  private func markFailed(
    queueFilePath: String?,
    id: String?,
    errorType: String,
    error: String,
    statusCode: Int?,
    fast: Bool
  ) -> (attempt: Int, nextAttemptAt: Int)? {
    var outcome: (attempt: Int, nextAttemptAt: Int)?
    updateQueue(queueFilePath: queueFilePath, id: id) { queue, item in
      let now = nowMillis()
      let attempt = (item["attempt"] as? Int ?? 0) + 1
      let nextAttemptAt = now + Int(Self.retryDelay(fast: fast, attempt: attempt) * 1000)
      item["status"] = "failed"
      item["attempt"] = attempt
      item["errorType"] = errorType
      item["lastFailedAtMillis"] = now
      item["nextAttemptAtMillis"] = nextAttemptAt
      item["updatedAtMillis"] = now
      item["lastError"] = error
      if let statusCode {
        item["lastStatusCode"] = statusCode
        // The server answered (with an error): the connection is alive.
        queue["lastResponseAtMillis"] = now
      } else {
        item.removeValue(forKey: "lastStatusCode")
      }
      if item["isCallEngine"] as? Bool == true {
        recordFailure(&queue, id: id ?? "", errorType: errorType, now: now)
      }
      outcome = (attempt: attempt, nextAttemptAt: nextAttemptAt)
    }
    return outcome
  }

  /// Consecutive captured-photo failures since the last server answer, read by
  /// Dart to decide when to warn the user. Any success or rejection removes it.
  /// Context-stream frames are not counted.
  private func recordFailure(_ queue: inout [String: Any], id: String, errorType: String, now: Int) {
    var streak = queue["failureStreak"] as? [String: Any] ?? ["sinceMillis": now]
    streak["count"] = (streak["count"] as? Int ?? 0) + 1
    streak["timeoutCount"] =
      errorType == "timeout" ? (streak["timeoutCount"] as? Int ?? 0) + 1 : 0
    streak["lastErrorType"] = errorType
    streak["lastFailedAtMillis"] = now
    var ids = streak["itemIds"] as? [String] ?? []
    if !ids.contains(id) && ids.count < 50 { ids.append(id) }
    streak["itemIds"] = ids
    queue["failureStreak"] = streak
  }

  private func updateQueue(
    queueFilePath: String?,
    id: String?,
    update: (inout [String: Any], inout [String: Any]) -> Void
  ) {
    guard let queueFilePath, let id else { return }
    queueFileLock.lock()
    defer { queueFileLock.unlock() }

    do {
      let queueURL = URL(fileURLWithPath: queueFilePath)
      let data = try Data(contentsOf: queueURL)
      var queue =
        (try JSONSerialization.jsonObject(with: data) as? [String: Any])
        ?? ["version": 1, "items": []]
      var items = queue["items"] as? [[String: Any]] ?? []
      // The item is gone when the session was cancelled mid-upload.
      guard let index = items.firstIndex(where: { ($0["id"] as? String) == id }) else {
        return
      }

      var item = items[index]
      update(&queue, &item)
      items[index] = item
      queue["items"] = items

      let out = try JSONSerialization.data(withJSONObject: queue)
      let tmpURL = URL(
        fileURLWithPath: "\(queueFilePath).ios-\(UUID().uuidString).tmp"
      )
      defer { try? FileManager.default.removeItem(at: tmpURL) }
      try out.write(to: tmpURL, options: .atomic)
      if FileManager.default.fileExists(atPath: queueURL.path) {
        try FileManager.default.replaceItemAt(queueURL, withItemAt: tmpURL)
      } else {
        try FileManager.default.moveItem(at: tmpURL, to: queueURL)
      }
    } catch {
      NSLog("AICycleBackgroundUploader: failed to update queue: %@", error.localizedDescription)
    }
  }

  // MARK: - URLSession delegate

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    let key = taskKey(session, dataTask)
    responseDataLock.lock()
    var current = responseDataByTaskKey[key] ?? Data()
    current.append(data)
    responseDataByTaskKey[key] = current
    responseDataLock.unlock()
  }

  /// Speed check (foreground only): from [speedCheckAfter] seconds into the
  /// body, cut an upload whose measured speed cannot finish within the
  /// session's total timeout instead of waiting for that timeout.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didSendBodyData bytesSent: Int64,
    totalBytesSent: Int64,
    totalBytesExpectedToSend: Int64
  ) {
    guard session !== backgroundSession, totalBytesExpectedToSend > 0,
      totalBytesSent < totalBytesExpectedToSend
    else { return }
    let key = taskKey(session, task)
    let now = Date()
    stateLock.lock()
    let start = sendStartByTaskKey[key] ?? now
    if sendStartByTaskKey[key] == nil { sendStartByTaskKey[key] = now }
    stateLock.unlock()

    let elapsed = now.timeIntervalSince(start)
    guard elapsed >= Self.speedCheckAfter else { return }
    let totalLimit = session.configuration.timeoutIntervalForResource
    let rate = Double(totalBytesSent) / elapsed
    let projected =
      rate > 0
      ? elapsed + Double(totalBytesExpectedToSend - totalBytesSent) / rate : .infinity
    guard projected > totalLimit else { return }

    stateLock.lock()
    let firstCut = tooSlowTaskKeys.insert(key).inserted
    stateLock.unlock()
    guard firstCut else { return }
    NSLog(
      "AICycleBackgroundUploader: upload too slow, cutting early: sent=%lld/%lld in %.0fs (needs ~%.0fs > %.0fs)",
      totalBytesSent, totalBytesExpectedToSend, elapsed, projected, totalLimit)
    task.cancel()
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    let responseBody = takeResponseBody(session, task)
    let key = taskKey(session, task)
    stateLock.lock()
    sendStartByTaskKey.removeValue(forKey: key)
    let tooSlow = tooSlowTaskKeys.remove(key) != nil
    stateLock.unlock()
    guard let item = decodeDescription(task) else { return }
    let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
    let id = item["id"] as? String
    let queueFilePath = item["queueFilePath"] as? String
    let filePath = item["filePath"] as? String
    if let bodyPath = item["bodyPath"] as? String {
      try? FileManager.default.removeItem(atPath: bodyPath)
    }

    // Cancelled by cancelAll / retryNow / an app state hand-off: whoever
    // cancelled owns what happens next. A speed-check cut is a timeout.
    if !tooSlow, let urlError = error as? URLError, urlError.code == .cancelled {
      return
    }

    if error == nil && (200..<300).contains(statusCode) {
      markSucceeded(
        queueFilePath: queueFilePath,
        id: id,
        statusCode: statusCode,
        responseBody: responseBody
      )
      NSLog(
        "AICycleBackgroundUploader: upload succeeded id=%@ HTTP %d bodyBytes=%d",
        id ?? "",
        statusCode,
        responseBody.count
      )
      if let filePath { try? FileManager.default.removeItem(atPath: filePath) }
      return
    }

    if error == nil && !Self.isRetryableHttp(statusCode)
      && !isRetryableEngineError(
        queueFilePath: queueFilePath, statusCode: statusCode, responseBody: responseBody)
    {
      // The server rejected this photo; retrying cannot help.
      markRejected(
        queueFilePath: queueFilePath,
        id: id,
        statusCode: statusCode,
        responseBody: responseBody
      )
      NSLog(
        "AICycleBackgroundUploader: upload rejected id=%@ HTTP %d body=%@",
        id ?? "",
        statusCode,
        String(responseBody.prefix(500))
      )
      if let filePath { try? FileManager.default.removeItem(atPath: filePath) }
      return
    }

    guard let filePath, FileManager.default.fileExists(atPath: filePath) else { return }

    let errorType: String
    let message: String
    if tooSlow {
      errorType = "timeout"
      message = "Upload too slow to finish in time"
    } else if error == nil {
      errorType = "server"
      message = "HTTP \(statusCode)"
    } else if let urlError = error as? URLError, urlError.code == .timedOut {
      errorType = "timeout"
      message = urlError.localizedDescription
    } else {
      errorType = "network"
      message = error?.localizedDescription ?? "Network upload failed"
    }

    let fast = readMode(queueFilePath: queueFilePath) == Self.fastMode
    guard
      let failure = markFailed(
        queueFilePath: queueFilePath,
        id: id,
        errorType: errorType,
        error: message,
        statusCode: error == nil ? statusCode : nil,
        fast: fast
      )
    else { return }
    NSLog(
      "AICycleBackgroundUploader: upload retry id=%@ attempt=%d type=%@ error=%@",
      id ?? "",
      failure.attempt,
      errorType,
      message
    )

    var retryItem = item
    retryItem["attempt"] = failure.attempt
    retryItem["nextAttemptAtMillis"] = failure.nextAttemptAt
    retryItem["mode"] = fast ? Self.fastMode : "background"
    retryItem.removeValue(forKey: "bodyPath")
    // Started directly instead of through scheduleUpload's duplicate check:
    // inside this delegate callback getAllTasks can still report the
    // just-completed task and would incorrectly suppress the retry.
    startUpload(retryItem, fast: fast, generation: currentGeneration())
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let handler = self.backgroundCompletionHandler
      self.backgroundCompletionHandler = nil
      handler?()
    }
  }
}

private enum UploadError: Error {
  case badArguments(String)
  case fileMissing
}

private extension FileHandle {
  func writeAll(_ string: String) throws {
    guard let data = string.data(using: .utf8) else { return }
    write(data)
  }
}
