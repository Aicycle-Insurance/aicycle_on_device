import Foundation
import UIKit

final class AICycleBackgroundUploader: NSObject, URLSessionDelegate, URLSessionTaskDelegate,
  URLSessionDataDelegate, @unchecked Sendable
{
  static let shared = AICycleBackgroundUploader()

  private let identifier = "com.aicycle.yolo.background-upload"
  private let ioQueue = DispatchQueue(label: "com.aicycle.yolo.background-upload.io", qos: .utility)
  private let queueFileLock = NSLock()
  private let responseDataLock = NSLock()
  private var backgroundCompletionHandler: (() -> Void)?
  private var responseDataByTaskId: [Int: Data] = [:]

  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = false
    configuration.httpMaximumConnectionsPerHost = 2
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }()

  func scheduleUpload(_ item: [String: Any], completion: ((Error?) -> Void)? = nil) {
    guard let id = item["id"] as? String else {
      completion?(UploadError.badArguments("Missing id"))
      return
    }

    session.getAllTasks { [weak self] tasks in
      guard let self else { return }
      if tasks.contains(where: { self.taskMatches($0, id: id) }) {
        completion?(nil)
        return
      }

      self.ioQueue.async {
        do {
          let task = try self.makeUploadTask(for: item)
          task.resume()
          NSLog("AICycleBackgroundUploader: scheduled upload id=%@", id)
          completion?(nil)
        } catch {
          completion?(error)
        }
      }
    }
  }

  func handleEvents(for identifier: String, completionHandler: @escaping () -> Void) {
    guard identifier == self.identifier else {
      completionHandler()
      return
    }
    backgroundCompletionHandler = completionHandler
    _ = session
  }

  private func makeUploadTask(for item: [String: Any]) throws -> URLSessionUploadTask {
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
    let task = session.uploadTask(with: request, fromFile: bodyURL)
    task.taskDescription = encodeDescription(description)
    if let attempt = item["attempt"] as? Int, attempt > 0 {
      task.earliestBeginDate = Date().addingTimeInterval(retryDelay(for: attempt))
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

  private func taskMatches(_ task: URLSessionTask, id: String) -> Bool {
    guard let description = task.taskDescription,
      let data = description.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return false
    }
    return json["id"] as? String == id
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

  private func retryDelay(for attempt: Int) -> TimeInterval {
    min(3600, pow(2.0, Double(attempt)) * 30)
  }

  private func escape(_ value: String) -> String {
    value.replacingOccurrences(of: "\"", with: "\\\"")
  }

  private func nowMillis() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
  }

  private func takeResponseBody(for task: URLSessionTask) -> String {
    responseDataLock.lock()
    let data = responseDataByTaskId.removeValue(forKey: task.taskIdentifier) ?? Data()
    responseDataLock.unlock()
    return String(data: data, encoding: .utf8) ?? ""
  }

  private func markSucceeded(
    queueFilePath: String?,
    id: String?,
    statusCode: Int,
    responseBody: String
  ) {
    guard let queueFilePath, let id else { return }
    updateQueueItem(queueFilePath: queueFilePath, id: id) { item in
      item["status"] = "succeeded"
      item["updatedAtMillis"] = nowMillis()
      item["responseStatusCode"] = statusCode
      if responseBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        item.removeValue(forKey: "responseBody")
      } else {
        item["responseBody"] = responseBody
      }
      item.removeValue(forKey: "lastError")
    }
  }

  private func markFailed(queueFilePath: String?, id: String?, error: String, attempt: Int) {
    guard let queueFilePath, let id else { return }
    updateQueueItem(queueFilePath: queueFilePath, id: id) { item in
      item["status"] = "failed"
      item["attempt"] = attempt
      item["nextAttemptAtMillis"] = nowMillis() + Int(retryDelay(for: attempt) * 1000)
      item["updatedAtMillis"] = nowMillis()
      item["lastError"] = error
    }
  }

  private func updateQueueItem(
    queueFilePath: String,
    id: String,
    update: (inout [String: Any]) -> Void
  ) {
    queueFileLock.lock()
    defer { queueFileLock.unlock() }

    do {
      let queueURL = URL(fileURLWithPath: queueFilePath)
      let data = try Data(contentsOf: queueURL)
      var queue =
        (try JSONSerialization.jsonObject(with: data) as? [String: Any])
        ?? ["version": 1, "items": []]
      var items = queue["items"] as? [[String: Any]] ?? []
      guard let index = items.firstIndex(where: { ($0["id"] as? String) == id }) else {
        return
      }

      var item = items[index]
      update(&item)
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

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    responseDataLock.lock()
    var current = responseDataByTaskId[dataTask.taskIdentifier] ?? Data()
    current.append(data)
    responseDataByTaskId[dataTask.taskIdentifier] = current
    responseDataLock.unlock()
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let item = decodeDescription(task) else { return }
    let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0
    let id = item["id"] as? String
    let queueFilePath = item["queueFilePath"] as? String
    let filePath = item["filePath"] as? String
    let bodyPath = item["bodyPath"] as? String
    let responseBody = takeResponseBody(for: task)

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
      if let bodyPath { try? FileManager.default.removeItem(atPath: bodyPath) }
      return
    }

    if let bodyPath { try? FileManager.default.removeItem(atPath: bodyPath) }
    if error == nil {
      // HTTP responses are final; network-level failures are the only retryable
      // case. Cache every response (including non-2xx) so Flutter can deliver
      // the body while alive or replay it after the next resume.
      let bodySnippet = String(responseBody.prefix(500))
      markSucceeded(
        queueFilePath: queueFilePath,
        id: id,
        statusCode: statusCode,
        responseBody: responseBody
      )
      NSLog(
        "AICycleBackgroundUploader: upload HTTP response delivered id=%@ HTTP %d body=%@",
        id ?? "",
        statusCode,
        bodySnippet
      )
      if let filePath { try? FileManager.default.removeItem(atPath: filePath) }
      return
    }

    guard let filePath, FileManager.default.fileExists(atPath: filePath) else { return }

    if let urlError = error as? URLError, urlError.code == .timedOut {
      markSucceeded(queueFilePath: queueFilePath, id: id, statusCode: 408, responseBody: "")
      try? FileManager.default.removeItem(atPath: filePath)
      NSLog("AICycleBackgroundUploader: upload timed out, treating as 408 id=%@", id ?? "")
      return
    }

    var retryItem = item
    let attempt = (item["attempt"] as? Int ?? 0) + 1
    markFailed(
      queueFilePath: queueFilePath,
      id: id,
      error: error?.localizedDescription ?? "Network upload failed",
      attempt: attempt
    )
    NSLog(
      "AICycleBackgroundUploader: upload retry id=%@ attempt=%d error=%@",
      id ?? "",
      attempt,
      error?.localizedDescription ?? "Network upload failed"
    )
    retryItem["attempt"] = attempt
    retryItem.removeValue(forKey: "bodyPath")
    // Schedule directly instead of calling scheduleUpload's duplicate check
    // from inside the completion delegate. At this point getAllTasks can still
    // report the just-completed task and incorrectly suppress the retry.
    ioQueue.async { [weak self] in
      guard let self else { return }
      do {
        let retryTask = try self.makeUploadTask(for: retryItem)
        retryTask.resume()
      } catch {
        NSLog(
          "AICycleBackgroundUploader: failed to schedule retry id=%@ error=%@",
          id ?? "",
          error.localizedDescription
        )
      }
    }
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
