// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  YOLOMultiTaskView — runs up to three YOLO models on a single camera stream simultaneously.
//  Each BasePredictor receives raw CVPixelBuffers on its own dispatch queue so all models
//  run concurrently via Apple's CoreML async scheduling.

import AVFoundation
import CoreImage
import CoreML
import CoreVideo
import UIKit
import UltralyticsYOLO

// MARK: - Per-predictor result adapter

/// Bridges ResultsListener / InferenceTimeListener callbacks back to a labelled slot
/// in YOLOMultiTaskView. All callbacks are re-dispatched onto `cameraQueue` so the
/// busy-flag bookkeeping stays on one serial queue (no locks needed).
final class MultiTaskPredictorAdapter: ResultsListener, InferenceTimeListener,
  @unchecked Sendable
{
  let taskName: String
  private let cameraQueue: DispatchQueue

  // Set by owner before use
  var onResult: ((YOLOResult) -> Void)?
  var onTime: ((Double, Double) -> Void)?

  init(taskName: String, cameraQueue: DispatchQueue) {
    self.taskName = taskName
    self.cameraQueue = cameraQueue
  }

  func on(result: YOLOResult) {
    let r = result
    cameraQueue.async { [weak self] in self?.onResult?(r) }
  }

  func on(inferenceTime: Double, fpsRate: Double) {
    let ms = inferenceTime
    let fps = fpsRate
    cameraQueue.async { [weak self] in self?.onTime?(ms, fps) }
  }
}

// MARK: - YOLOMultiTaskView

/// A UIView that hosts a single AVCaptureSession and dispatches each incoming
/// camera frame to up to three independent YOLO predictors simultaneously.
@MainActor
public class YOLOMultiTaskView: UIView {

  // MARK: Camera

  private let captureSession = AVCaptureSession()
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private let photoOutput = AVCapturePhotoOutput()
  private var photoCaptureCompletion: ((Data?) -> Void)?
  /// Visible viewport (normalized [0,1] rect in preview space) to crop the next
  /// still to; nil = keep the full frame.
  private var pendingCrop: CGRect?
  /// Preview view size (points) snapshotted when capture is requested — used to
  /// map the normalized crop into photo pixels under aspect-fill.
  private var pendingPreviewSize: CGSize = .zero
  private var pendingJpegQuality: CGFloat = 0.8
  private var captureDevice: AVCaptureDevice?

  /// Serial queue for camera delegate callbacks and busy-flag mutations only.
  let cameraQueue = DispatchQueue(label: "yolo.multi-task.camera", qos: .userInteractive)

  /// Shared serial queue for all YOLO predictors — only one model executes on GPU/ANE
  /// at any given time, eliminating resource contention and thermal/current spikes.
  private let inferenceQueue = DispatchQueue(label: "yolo.infer.shared", qos: .userInteractive)

  /// Identifies which predictor slot a result came from.
  private enum Slot { case detect, classify, third }

  // MARK: Predictors

  var detectPredictor:   BasePredictor?
  var classifyPredictor: BasePredictor?
  var thirdPredictor:    BasePredictor?
  var thirdTaskType:     String = "detect"
  /// Stable identifier for the third predictor's results, so consumers can tell two detect
  /// models apart (the primary detect model reports `modelId == "detect"`).
  var thirdModelId:      String = "detect2"

  // Phase-based gating (cameraQueue). Defaults match the initial framing phase:
  //   panorama/framing  → carDamage OFF, isPanoramicPhase ON
  //   inspection        → carDamage ON,  isPanoramicPhase OFF
  // carCorner (classify) and carPart (third) always run.
  private var detectEnabled = false
  private var isPanoramicPhase = true

  /// One-frame-deep back-pressure: true while any predictor is executing on inferenceQueue.
  /// Accessed only on cameraQueue.
  private var isInferring = false

  /// Round-robin scheduling ring: 2 DETECT : 1 THIRD : 1 CLASSIFY.
  /// In panoramic phase (detectEnabled = false), DETECT candidates are skipped
  /// and execution naturally interleaves between THIRD and CLASSIFY.
  private let rrCandidates: [Slot] = [.detect, .third, .detect, .classify]
  private var rrCursor = 0

  // MARK: Nhịp chạy model theo bậc nhiệt (cameraQueue)

  // Mỗi bảng có 4 phần tử, index theo ThermalTier.rawValue:
  //   [normal, warm, hot, critical]
  // Giá trị là khoảng cách tối thiểu (giây) giữa 2 lần chạy.
  // Máy càng nóng, nhịp càng thưa → GPU/ANE có thời gian nghỉ giữa các lần inference.
  // Ở bậc .normal: classify ~3.0 fps (0.33s), carPart 5.0 fps (0.20s) khi căn toàn cảnh
  // rồi hạ về ~3.3 fps (0.30s) khi soi tổn thất, carDamage ~6.7 fps (0.15s).

  /// carDamage — model chính, tốn nhiều nhất.
  private static let detectMinInferenceIntervals: [CFTimeInterval] = [0.15, 0.20, 0.30, 0.50]

  /// carCorner.
  private static let classifyMinInferenceIntervals: [CFTimeInterval] = [0.33, 0.40, 0.50, 0.65]

  // carPart phải chạy nhanh hơn `_carPartFlickerGrace` (600 ms) phía Dart — nếu
  // thưa hơn thì `_seenRecently` không bao giờ đúng và luồng canh khung ảnh toàn
  // cảnh đứng hẳn.
  private static let thirdPanoramicMinInferenceIntervals: [CFTimeInterval] = [0.20, 0.25, 0.35, 0.45]
  private static let thirdInspectionMinInferenceIntervals: [CFTimeInterval] = [0.30, 0.40, 0.50, 0.65]

  private var lastDetectTime: CFTimeInterval = 0
  private var lastClassifyTime: CFTimeInterval = 0
  private var lastThirdTime: CFTimeInterval = 0

  // MARK: Hạ nhiệt

  /// Bậc nhiệt hiện tại, dùng để tra các bảng nhịp ở trên. Owned by cameraQueue
  /// giống mọi state khác trong đường xử lý frame.
  private var thermalTier: ThermalTier = .normal

  private lazy var thermalGovernor = ThermalGovernor { [weak self] tier in
    // Callback chạy trên main queue; hop sang cameraQueue vì `thermalTier` thuộc
    // về queue đó.
    guard let self else { return }
    self.cameraQueue.async { [weak self] in self?.thermalTier = tier }
    DispatchQueue.main.async { [weak self] in
      self?.onMultiTaskStream?(YOLOMultiTaskView.thermalEvent(tier))
    }
  }

  // Context stream sampling (cameraQueue only)
  private static let streamInterval: CFTimeInterval = 2.0
  private static let streamJpegQuality: CGFloat = 0.70
  private static let jpegEncodeContext = CIContext()
  private var streamEnabled = false
  private var streamDirPath = ""
  private var isCapturingAnchor = false
  private var lastStreamSampleTime: CFTimeInterval = 0

  private lazy var detectAdapter   = MultiTaskPredictorAdapter(taskName: "detect",   cameraQueue: cameraQueue)
  private lazy var classifyAdapter = MultiTaskPredictorAdapter(taskName: "classify", cameraQueue: cameraQueue)
  private lazy var thirdAdapter    = MultiTaskPredictorAdapter(taskName: "third",    cameraQueue: cameraQueue)

  // MARK: Per-task FPS tracking (cameraQueue)

  private var detectLastResultTime:   Double = 0
  private var classifyLastResultTime: Double = 0
  private var thirdLastResultTime:    Double = 0

  private var detectFps:   Double = 0
  private var classifyFps: Double = 0
  private var thirdFps:    Double = 0

  // Camera FPS (cameraQueue)
  private var camFrameCount = 0
  private var camFpsWindowStart: Double = 0
  private var camFps: Double = 0

  // MARK: Callback

  /// Called on the main thread with a stream-data dict. Keys: "type", "fps", "cameraFps",
  /// "processingTimeMs", plus task-specific keys ("detections", "classification", etc.).
  var onMultiTaskStream: (([String: Any]) -> Void)?

  // MARK: Loading indicator

  public let activityIndicator = UIActivityIndicatorView(style: .large)
  private var loadedCount = 0
  private var expectedCount = 0

  // MARK: Init

  public override init(frame: CGRect) {
    super.init(frame: frame)
    setupUI()
    wireAdapters()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    setupUI()
    wireAdapters()
  }

  private func setupUI() {
    backgroundColor = .black
    activityIndicator.color = .white
    activityIndicator.startAnimating()
    addSubview(activityIndicator)
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    previewLayer?.frame = bounds
    activityIndicator.center = CGPoint(x: bounds.midX, y: bounds.midY)
  }

  // MARK: - Adapter wiring

  private func wireAdapters() {
    detectAdapter.onResult   = { [weak self] r in self?.handleResult(r, slot: .detect) }
    classifyAdapter.onResult = { [weak self] r in self?.handleResult(r, slot: .classify) }
    thirdAdapter.onResult    = { [weak self] r in self?.handleResult(r, slot: .third) }

    detectAdapter.onTime   = { [weak self] _, fps in self?.detectFps   = fps }
    classifyAdapter.onTime = { [weak self] _, fps in self?.classifyFps = fps }
    thirdAdapter.onTime    = { [weak self] _, fps in self?.thirdFps    = fps }
  }

  // MARK: - Result handling (cameraQueue)

  private func handleResult(_ result: YOLOResult, slot: Slot) {
    let now = CACurrentMediaTime()
    let task: String
    let modelId: String
    var taskFps: Double = 0

    // Reset single inference busy state (cameraQueue)
    isInferring = false

    switch slot {
    case .detect:
      detectPredictor?.isUpdating = false
      if detectLastResultTime > 0 {
        let dt = now - detectLastResultTime
        if dt > 0 { detectFps = 1.0 / dt }
      }
      detectLastResultTime = now
      taskFps = detectFps
      task = "detect"
      modelId = "detect"
    case .classify:
      classifyPredictor?.isUpdating = false
      if classifyLastResultTime > 0 {
        let dt = now - classifyLastResultTime
        if dt > 0 { classifyFps = 1.0 / dt }
      }
      classifyLastResultTime = now
      taskFps = classifyFps
      task = "classify"
      modelId = "classify"
    case .third:
      thirdPredictor?.isUpdating = false
      if thirdLastResultTime > 0 {
        let dt = now - thirdLastResultTime
        if dt > 0 { thirdFps = 1.0 / dt }
      }
      thirdLastResultTime = now
      taskFps = thirdFps
      task = thirdTaskType
      modelId = thirdModelId
    }

    let camFpsSnapshot = camFps
    let streamData = buildStreamData(
      result: result, task: task, modelId: modelId, fps: taskFps, cameraFps: camFpsSnapshot)

    DispatchQueue.main.async { [weak self] in
      self?.onMultiTaskStream?(streamData)
    }
  }

  /// Updates the visible viewport (retained for backward compatibility).
  func setOcrViewport(top: CGFloat, bottom: CGFloat) {
    // No-op: OCR removed
  }

  /// Phase-based gating: inspection runs carDamage; framing/panorama
  /// sets isPanoramicPhase and stops carDamage. carCorner/carPart always run.
  func setInspectionActive(_ active: Bool) {
    cameraQueue.async { [weak self] in
      self?.detectEnabled = active
      self?.isPanoramicPhase = !active
    }
  }

  func startContextStream(dirPath: String) {
    cameraQueue.async { [weak self] in
      self?.streamDirPath = dirPath
      self?.streamEnabled = true
      self?.lastStreamSampleTime = 0
    }
  }

  func stopContextStream() {
    cameraQueue.async { [weak self] in
      self?.stopContextStreamInternal()
    }
  }

  func setCapturingAnchor(_ active: Bool) {
    cameraQueue.async { [weak self] in
      self?.isCapturingAnchor = active
    }
  }

  private func stopContextStreamInternal() {
    streamEnabled = false
    streamDirPath = ""
    lastStreamSampleTime = 0
    isCapturingAnchor = false
  }

  private func maybeSampleContextStream(from sampleBuffer: CMSampleBuffer, now: CFTimeInterval) {
    guard streamEnabled, !isCapturingAnchor else { return }
    guard now - lastStreamSampleTime >= Self.streamInterval else { return }
    let dir = streamDirPath
    guard !dir.isEmpty else { return }
    lastStreamSampleTime = now

    let buf = sampleBuffer
    let callback = onMultiTaskStream
    DispatchQueue.global(qos: .utility).async {
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(buf),
        let jpegData = Self.encodeJPEG(from: pixelBuffer, quality: Self.streamJpegQuality)
      else { return }
      let fileName = "stream_\(Int(now * 1000)).jpg"
      let path = (dir as NSString).appendingPathComponent(fileName)
      do {
        try FileManager.default.createDirectory(
          atPath: dir,
          withIntermediateDirectories: true
        )
        try jpegData.write(to: URL(fileURLWithPath: path), options: .atomic)
        let payload: [String: Any] = ["type": "streamFrame", "filePath": path]
        DispatchQueue.main.async { callback?(payload) }
      } catch {
        NSLog("YOLOMultiTaskView: context stream sample failed: %@", error.localizedDescription)
      }
    }
  }

  private nonisolated static func encodeJPEG(
    from pixelBuffer: CVPixelBuffer,
    quality: CGFloat
  ) -> Data? {
    let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
    guard let cgImage = jpegEncodeContext.createCGImage(ciImage, from: ciImage.extent) else {
      return nil
    }
    return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
  }

  // MARK: - Stream data builder

  /// Sự kiện báo bậc nhiệt hiện tại lên Dart (`type == "thermal"`). Bắn khi bậc
  /// đổi và một lần lúc camera khởi động, để host biết SDK đang tự hạ nhịp.
  nonisolated static func thermalEvent(_ tier: ThermalTier) -> [String: Any] {
    [
      "type": "thermal",
      "modelId": "thermal",
      "level": tier.rawValue,
      "state": tier.label,
      "throttled": tier != .normal,
    ]
  }

  private func buildStreamData(
    result: YOLOResult, task: String, modelId: String, fps: Double, cameraFps: Double
  ) -> [String: Any] {
    var map: [String: Any] = [
      "type": task,
      "modelId": modelId,
      "fps": fps,
      "cameraFps": cameraFps,
      "processingTimeMs": result.speed * 1000,
    ]

    switch task {
    case "classify":
      if let probs = result.probs {
        var top5: [[String: Any]] = []
        for i in 0..<min(probs.top5Labels.count, probs.top5Confs.count) {
          top5.append(["name": probs.top5Labels[i], "confidence": Double(probs.top5Confs[i])])
        }
        map["classification"] = [
          "top1": probs.top1Label,
          "top1Confidence": Double(probs.top1Conf),
          "top5": top5,
        ]
      }
    default:
      // detect, segment, pose, obb — all have boxes.
      // The custom Vietnamese damage labels only apply to the primary detect model; any
      // other detect model reports its own class names via box.cls.
      let useCustomNames = (modelId == "detect")
      let classNames = ["Móp/bẹp", "Vỡ/nứt", "Thủng/rách", "Trầy/xước"]
      var detections: [[String: Any]] = []
      for box in result.boxes.prefix(50) {
        let name = (useCustomNames && box.index < classNames.count) ? classNames[box.index] : box.cls
        detections.append([
          "className": name,
          "confidence": Double(box.conf),
          "normalizedBox": [
            "left":   Double(box.xywhn.minX),
            "top":    Double(box.xywhn.minY),
            "right":  Double(box.xywhn.maxX),
            "bottom": Double(box.xywhn.maxY),
          ],
        ])
      }
      map["detections"] = detections
    }

    return map
  }

  // MARK: - Model loading

  /// Load two or three models concurrently. `thirdModelPath` / `thirdModelTask` are optional.
  /// `completion` fires on the main thread once all requested models finish loading.
  /// Camera starts automatically after all models are ready.
  func loadModels(
    detectPath: String,
    classifyPath: String,
    thirdModelPath: String? = nil,
    thirdModelTask: String = "detect",
    ocrModelPath: String? = nil,
    ocrConfidenceThreshold: Double = 0.85,
    useGpu: Bool = true,
    detectConfidenceThreshold: Double = 0.25,
    detectIouThreshold: Double = 0.7,
    classifyConfidenceThreshold: Double = 0.25,
    thirdConfidenceThreshold: Double = 0.25,
    thirdIouThreshold: Double = 0.7,
    cameraPosition: AVCaptureDevice.Position = .back,
    completion: @escaping () -> Void
  ) {
    self.thirdTaskType = thirdModelTask
    expectedCount = thirdModelPath != nil ? 3 : 2
    loadedCount = 0

    func tryDone() {
      loadedCount += 1
      if loadedCount == expectedCount {
        DispatchQueue.main.async { [weak self] in
          self?.activityIndicator.stopAnimating()
          self?.startCamera(position: cameraPosition)
          completion()
        }
      }
    }

    load(path: detectPath, task: .detect, useGpu: useGpu) { [weak self] p in
      if p == nil { NSLog("YOLOMultiTaskView: ⚠️ detect predictor is nil after load") }
      else { NSLog("YOLOMultiTaskView: ✅ detect predictor loaded") }
      p?.setConfidenceThreshold(confidence: detectConfidenceThreshold)
      p?.setIouThreshold(iou: detectIouThreshold)
      self?.detectPredictor = p
      tryDone()
    }

    load(path: classifyPath, task: .classify, useGpu: useGpu) { [weak self] p in
      if p == nil { NSLog("YOLOMultiTaskView: ⚠️ classify predictor is nil after load") }
      else { NSLog("YOLOMultiTaskView: ✅ classify predictor loaded") }
      p?.setConfidenceThreshold(confidence: classifyConfidenceThreshold)
      self?.classifyPredictor = p
      tryDone()
    }

    if let thirdPath = thirdModelPath {
      let yoloTask = yoloTaskFromString(thirdModelTask)
      load(path: thirdPath, task: yoloTask, useGpu: useGpu) { [weak self] p in
        if p == nil { NSLog("YOLOMultiTaskView: ⚠️ third predictor (\(thirdModelTask)) is nil after load") }
        else { NSLog("YOLOMultiTaskView: ✅ third predictor (\(thirdModelTask)) loaded") }
        p?.setConfidenceThreshold(confidence: thirdConfidenceThreshold)
        p?.setIouThreshold(iou: thirdIouThreshold)
        self?.thirdPredictor = p
        tryDone()
      }
    }
  }

  private func yoloTaskFromString(_ task: String) -> YOLOTask {
    switch task.lowercased() {
    case "classify": return .classify
    case "segment":  return .segment
    case "pose":     return .pose
    case "obb":      return .obb
    default:         return .detect
    }
  }

  private func load(
    path: String, task: YOLOTask, useGpu: Bool,
    completion: @escaping (BasePredictor?) -> Void
  ) {
    guard let url = resolveModelURL(path) else {
      NSLog("YOLOMultiTaskView: model not found: %@", path)
      completion(nil)
      return
    }
    BasePredictor.create(for: task, modelURL: url, isRealTime: true, useGpu: useGpu) { result in
      switch result {
      case .success(let p):
        let bp = p as? BasePredictor
        bp?.capturesOriginalImage = false
        completion(bp)
      case .failure(let err):
        NSLog("YOLOMultiTaskView: load failed for %@: %@", path, err.localizedDescription)
        completion(nil)
      }
    }
  }

  private func resolveModelURL(_ nameOrPath: String) -> URL? {
    let lc = nameOrPath.lowercased()
    let fm = FileManager.default

    // Direct path: .mlmodel can be a file. .mlpackage/.mlmodelc are bundle
    // directories; zip archives should already have been extracted by Dart.
    if lc.hasSuffix(".mlmodel") {
      let u = URL(fileURLWithPath: nameOrPath)
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: u.path, isDirectory: &isDir) {
        return compiledModelURL(for: u) ?? u
      }
    }

    if lc.hasSuffix(".mlmodelc") || lc.hasSuffix(".mlpackage") {
      let u = URL(fileURLWithPath: nameOrPath)
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: u.path, isDirectory: &isDir) {
        if isDir.boolValue { return u }
        NSLog("YOLOMultiTaskView: ⚠️ path is a file (unextracted zip?): %@", nameOrPath)
        return nil
      }
    }

    // .mlpackage.zip: should have been extracted by Dart resolver, but check derived path
    if lc.hasSuffix(".mlpackage.zip") {
      let derived = URL(fileURLWithPath: String(nameOrPath.dropLast(4))) // drop ".zip"
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: derived.path, isDirectory: &isDir), isDir.boolValue {
        return derived
      }
      return nil
    }

    if let u = Bundle.main.url(forResource: nameOrPath, withExtension: "mlmodelc") { return u }
    if let u = Bundle.main.url(forResource: nameOrPath, withExtension: "mlpackage") { return u }
    return nil
  }

  private func compiledModelURL(for sourceURL: URL) -> URL? {
    let fm = FileManager.default
    let compiledURL = sourceURL.deletingPathExtension().appendingPathExtension("mlmodelc")

    if fm.fileExists(atPath: compiledURL.path) {
      do {
        let sourceAttrs = try fm.attributesOfItem(atPath: sourceURL.path)
        let compiledAttrs = try fm.attributesOfItem(atPath: compiledURL.path)
        let sourceDate = sourceAttrs[.modificationDate] as? Date ?? .distantPast
        let compiledDate = compiledAttrs[.modificationDate] as? Date ?? .distantPast
        if compiledDate >= sourceDate {
          return compiledURL
        }
        try fm.removeItem(at: compiledURL)
      } catch {
        NSLog(
          "YOLOMultiTaskView: ⚠️ failed to inspect cached compiled model %@: %@",
          compiledURL.path,
          error.localizedDescription
        )
        try? fm.removeItem(at: compiledURL)
      }
    }

    do {
      let temporaryCompiledURL = try MLModel.compileModel(at: sourceURL)
      if fm.fileExists(atPath: compiledURL.path) {
        try fm.removeItem(at: compiledURL)
      }
      try fm.copyItem(at: temporaryCompiledURL, to: compiledURL)
      NSLog("YOLOMultiTaskView: ✅ compiled mlmodel: %@", compiledURL.path)
      return compiledURL
    } catch {
      NSLog(
        "YOLOMultiTaskView: ⚠️ failed to compile mlmodel %@: %@",
        sourceURL.path,
        error.localizedDescription
      )
      return nil
    }
  }

  // MARK: - Camera

  private func startCamera(position: AVCaptureDevice.Position) {
    let pos = position
    cameraQueue.async { [weak self] in self?.setupCamera(position: pos) }
  }

  private func setupCamera(position: AVCaptureDevice.Position) {
    captureSession.beginConfiguration()
    // A single AVCaptureSession has one active format shared by the video-data output
    // (model stream) and the photo output. Use FullHD so still captures are 1920x1080;
    // each predictor resizes incoming frames to its own network input internally, so the
    // live stream effectively runs at the model's input resolution regardless of preset.
    captureSession.sessionPreset = .hd1920x1080

    guard let device = bestCaptureDevice(position: position),
      let input = try? AVCaptureDeviceInput(device: device),
      captureSession.canAddInput(input)
    else {
      captureSession.commitConfiguration()
      return
    }
    captureDevice = device
    captureSession.addInput(input)

    let output = AVCaptureVideoDataOutput()
    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
    ]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: cameraQueue)
    if captureSession.canAddOutput(output) { captureSession.addOutput(output) }
    if captureSession.canAddOutput(photoOutput) { captureSession.addOutput(photoOutput) }

    // Rotate the pixel buffer to landscape so the model always receives wide frames
    // regardless of how the user holds the device. The preview connection is left at
    // its default (.portrait) so the viewfinder appears upright to the user.
    if let conn = output.connection(with: .video) {
      conn.videoOrientation = .landscapeRight
    }
    if let conn = photoOutput.connection(with: .video) {
      conn.videoOrientation = .landscapeRight
    }

    captureSession.commitConfiguration()

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let preview = AVCaptureVideoPreviewLayer(session: self.captureSession)
      preview.videoGravity = .resizeAspectFill
      preview.frame = self.bounds
      self.layer.insertSublayer(preview, at: 0)
      self.previewLayer = preview

      // Bắt đầu theo dõi nhiệt cùng lúc camera lên hình, và báo bậc nhiệt khởi
      // điểm — máy có thể đã nóng sẵn từ trước khi mở màn camera.
      self.thermalGovernor.start()
      let tier = self.thermalGovernor.tier
      self.cameraQueue.async { [weak self] in self?.thermalTier = tier }
      self.onMultiTaskStream?(YOLOMultiTaskView.thermalEvent(tier))
    }

    captureSession.startRunning()
    camFpsWindowStart = CACurrentMediaTime()
  }

  public func capturePhoto(
    crop: CGRect? = nil,
    quality: CGFloat = 0.8,
    completion: @escaping (Data?) -> Void
  ) {
    photoCaptureCompletion = completion
    pendingCrop = crop
    pendingJpegQuality = quality
    // Read the preview bounds on the main thread (this is called from the
    // MethodChannel handler, i.e. main); the delegate may run off-main.
    pendingPreviewSize = bounds.size
    let settings = AVCapturePhotoSettings()
    settings.flashMode = .off
    cameraQueue.async { [weak self] in
      guard let self else { completion(nil); return }
      self.photoOutput.capturePhoto(with: settings, delegate: self)
    }
  }

  public func capturePhotoToFile(
    path: String,
    crop: CGRect? = nil,
    quality: CGFloat = 0.8,
    thumbnailPath: String? = nil,
    thumbnailMaxSize: CGFloat = 160,
    completion: @escaping (String?) -> Void
  ) {
    capturePhoto(crop: crop, quality: quality) { data in
      guard let data else {
        completion(nil)
        return
      }
      DispatchQueue.global(qos: .utility).async {
        do {
          let url = URL(fileURLWithPath: path)
          try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
          )
          try data.write(to: url, options: .atomic)
          if let thumbnailPath {
            try? self.writeThumbnail(
              data: data,
              path: thumbnailPath,
              maxSize: thumbnailMaxSize
            )
          }
          completion(url.path)
        } catch {
          NSLog("YOLOMultiTaskView: capturePhotoToFile failed: %@", error.localizedDescription)
          completion(nil)
        }
      }
    }
  }

  private nonisolated func writeThumbnail(data: Data, path: String, maxSize: CGFloat) throws {
    guard let image = UIImage(data: data) else { return }
    let longest = max(image.size.width, image.size.height)
    guard longest > 0 else { return }
    let scale = min(1, maxSize / longest)
    let size = CGSize(
      width: max(1, image.size.width * scale),
      height: max(1, image.size.height * scale)
    )
    let renderer = UIGraphicsImageRenderer(size: size)
    let thumbnailData = renderer.jpegData(withCompressionQuality: 0.65) { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try thumbnailData.write(to: url, options: .atomic)
  }

  @discardableResult
  public func setTorchMode(_ enabled: Bool) -> Bool {
    guard let device = captureDevice, device.hasTorch else { return false }
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      if enabled {
        try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
      } else {
        device.torchMode = .off
      }
      return device.torchMode == .on
    } catch {
      NSLog("YOLOMultiTaskView: Failed to set torch mode: %@", error.localizedDescription)
      return false
    }
  }

  public func stopCamera() {
    cameraQueue.async { [weak self] in
      self?.stopContextStreamInternal()
      self?.captureSession.stopRunning()
    }
  }

  /// Full resource release: stops camera, removes preview layer, nils predictors and callback.
  /// Call from the platform view's dispose/deinit path so GPU/ANE memory is freed promptly
  /// even if deinit is delayed by a retain cycle in the Flutter EventChannel stream handler.
  public func releaseResources() {
    onMultiTaskStream = nil
    thermalGovernor.stop()
    cameraQueue.async { [weak self] in
      self?.stopContextStreamInternal()
      self?.captureSession.stopRunning()
    }
    DispatchQueue.main.async { [weak self] in
      self?.previewLayer?.removeFromSuperlayer()
      self?.previewLayer = nil
    }
    // Thả tham chiếu predictor ở luồng nền: dealloc model CoreML (giải phóng ANE/
    // GPU) có thể tốn nhiều ms, chạy trên main thread sẽ treo UI khi rời màn camera.
    let toRelease = [detectPredictor, classifyPredictor, thirdPredictor]
    detectPredictor = nil
    classifyPredictor = nil
    thirdPredictor = nil
    DispatchQueue.global(qos: .utility).async {
      // Giữ strong ref tới hết block rồi mới thả → dealloc xảy ra ở nền (nếu đây
      // là tham chiếu cuối cùng).
      _ = toRelease.count
    }
  }

  deinit {
    if captureSession.isRunning {
      captureSession.stopRunning()
    }
  }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension YOLOMultiTaskView: AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

  public func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    // All mutable state accesses in this extension run on cameraQueue.

    // Track camera FPS
    let now = CACurrentMediaTime()
    camFrameCount += 1
    let elapsed = now - camFpsWindowStart
    if elapsed >= 0.5 {
      camFps = Double(camFrameCount) / elapsed
      camFrameCount = 0
      camFpsWindowStart = now
    }

    maybeSampleContextStream(from: sampleBuffer, now: now)

    // Phase 1: Back-pressure check. Nếu inferenceQueue đang bận chạy model trước
    // đó, bỏ qua frame hiện tại ngay lập tức để không tích tụ hàng đợi (zero lag).
    if isInferring { return }

    // Phase 2: Lập lịch xoay vòng (Round-Robin). Tìm candidate kế tiếp đủ điều kiện
    // (đã load, đúng phase, đủ khoảng cách minInterval theo bậc nhiệt).
    let tier = thermalTier.rawValue
    guard let slot = nextEligibleSlot(now: now, tier: tier) else { return }

    isInferring = true

    let predictor: BasePredictor
    let adapter: MultiTaskPredictorAdapter

    switch slot {
    case .detect:
      guard let p = detectPredictor else { isInferring = false; return }
      lastDetectTime = now
      predictor = p
      adapter = detectAdapter
    case .classify:
      guard let p = classifyPredictor else { isInferring = false; return }
      lastClassifyTime = now
      predictor = p
      adapter = classifyAdapter
    case .third:
      guard let p = thirdPredictor else { isInferring = false; return }
      lastThirdTime = now
      predictor = p
      adapter = thirdAdapter
    }

    predictor.isUpdating = true
    let buf = sampleBuffer
    inferenceQueue.async {
      predictor.predict(sampleBuffer: buf, onResultsListener: adapter, onInferenceTime: adapter)
    }
  }

  private func isEligible(slot: Slot, now: CFTimeInterval, tier: Int) -> Bool {
    switch slot {
    case .detect:
      guard let p = detectPredictor, detectEnabled, !p.isUpdating else { return false }
      let minInterval = Self.detectMinInferenceIntervals[tier]
      return minInterval == 0 || now - lastDetectTime >= minInterval
    case .classify:
      guard let p = classifyPredictor, !p.isUpdating else { return false }
      return now - lastClassifyTime >= Self.classifyMinInferenceIntervals[tier]
    case .third:
      guard let p = thirdPredictor, !p.isUpdating else { return false }
      let minInterval = isPanoramicPhase
        ? Self.thirdPanoramicMinInferenceIntervals[tier]
        : Self.thirdInspectionMinInferenceIntervals[tier]
      return now - lastThirdTime >= minInterval
    }
  }

  private func nextEligibleSlot(now: CFTimeInterval, tier: Int) -> Slot? {
    let size = rrCandidates.count
    for step in 0..<size {
      let index = (rrCursor + step) % size
      let slot = rrCandidates[index]
      if isEligible(slot: slot, now: now, tier: tier) {
        rrCursor = (index + 1) % size
        return slot
      }
    }
    return nil
  }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension YOLOMultiTaskView: AVCapturePhotoCaptureDelegate {
  public func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    let completion = photoCaptureCompletion
    photoCaptureCompletion = nil
    let crop = pendingCrop
    let previewSize = pendingPreviewSize
    let quality = pendingJpegQuality
    pendingCrop = nil
    guard error == nil, let data = photo.fileDataRepresentation() else {
      completion?(nil)
      return
    }
    // No crop requested → keep the original bytes (only normalize orientation).
    guard let src = UIImage(data: data) else {
      completion?(data)
      return
    }
    if crop == nil, src.imageOrientation == .up {
      completion?(data)
      return
    }

    // Bake orientation so the CGImage is upright (top-left origin) before cropping.
    let upright: UIImage
    if src.imageOrientation == .up {
      upright = src
    } else {
      let renderer = UIGraphicsImageRenderer(size: src.size)
      upright = renderer.image { _ in
        src.draw(in: CGRect(origin: .zero, size: src.size))
      }
    }

    guard let crop, previewSize.width > 0, previewSize.height > 0,
      let cg = upright.cgImage
    else {
      completion?(upright.jpegData(compressionQuality: quality))
      return
    }

    // Map the normalized preview rect into photo pixels under aspect-fill (cover).
    let wp = CGFloat(cg.width), hp = CGFloat(cg.height)
    let wv = previewSize.width, hv = previewSize.height
    let rect: CGRect
    if (wp >= hp) != (wv >= hv) {
      // Preview is portrait but the still is landscape (photo connection is
      // .landscapeRight = the preview rotated 90° clockwise). The preview's
      // vertical axis (where the top/bottom bars live) maps to the photo's
      // horizontal axis, so the crop must be transposed.
      let s = max(wv / hp, hv / wp)
      let offU = (hp * s - wv) / 2  // overflow along preview width  → photo height
      let offV = (wp * s - hv) / 2  // overflow along preview height → photo width
      let u0 = (crop.minX * wv + offU) / s
      let u1 = (crop.maxX * wv + offU) / s
      let v0 = (crop.minY * hv + offV) / s
      let v1 = (crop.maxY * hv + offV) / s
      let x = max(0, v0), y = max(0, hp - u1)
      rect = CGRect(
        x: x, y: y,
        width: min(wp, v1) - x,
        height: min(hp, hp - u0) - y)
    } else {
      let scale = max(wv / wp, hv / hp)
      let offX = (wp * scale - wv) / 2
      let offY = (hp * scale - hv) / 2
      let x = max(0, (crop.minX * wv + offX) / scale)
      let y = max(0, (crop.minY * hv + offY) / scale)
      rect = CGRect(
        x: x, y: y,
        width: min(wp, (crop.maxX * wv + offX) / scale) - x,
        height: min(hp, (crop.maxY * hv + offY) / scale) - y)
    }

    guard rect.width > 0, rect.height > 0, let cropped = cg.cropping(to: rect) else {
      completion?(upright.jpegData(compressionQuality: quality))
      return
    }
    completion?(UIImage(cgImage: cropped).jpegData(compressionQuality: quality))
  }
}
