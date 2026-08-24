// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

//  YOLOMultiTaskView — runs up to three YOLO models on a single camera stream simultaneously.
//  Each BasePredictor receives raw CVPixelBuffers on its own dispatch queue so all models
//  run concurrently via Apple's CoreML async scheduling.

import AVFoundation
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

  /// Per-predictor inference queues — each predictor runs concurrently.
  private let detectQueue  = DispatchQueue(label: "yolo.infer.detect",   qos: .userInteractive)
  private let classifyQueue = DispatchQueue(label: "yolo.infer.classify", qos: .userInteractive)
  private let thirdQueue   = DispatchQueue(label: "yolo.infer.third",    qos: .userInteractive)

  // MARK: Predictors

  var detectPredictor:   BasePredictor?
  var classifyPredictor: BasePredictor?
  var thirdPredictor:    BasePredictor?
  var thirdTaskType:     String = "detect"
  /// Stable identifier for the third predictor's results, so consumers can tell two detect
  /// models apart (the primary detect model reports `modelId == "detect"`).
  var thirdModelId:      String = "detect2"

  // MARK: License-plate OCR (gated by the carPart / third detector)

  /// Standalone CoreML recognizer (not a YOLO predictor). When set, every carPart
  /// frame that contains a `"Biển số xe"` box is cropped and run through OCR; the
  /// result is streamed to Dart as a separate `type == "ocr"` event used purely as
  /// a framing signal (a readable plate ⇒ this frame is a good panoramic shot).
  private var ocrModel: LicensePlateOCR?
  /// carPart's class name for the license plate (matches the Dart gating logic).
  private static let licensePlateClass = "Biển số xe"
  /// Visible viewport (preview-space vertical band, which maps to the box X axis —
  /// see `_filterToViewport` in the Dart controller). OCR only considers plate
  /// boxes fully inside this band so a readable plate is guaranteed to sit inside
  /// the saved (viewport-cropped) photo. Defaults to the full frame until set.
  private var ocrViewportTop: CGFloat = 0
  private var ocrViewportBottom: CGFloat = 1
  /// Inset from the viewport band edge (buffer X = preview-vertical). Rejects a
  /// plate clipped near the top/bottom bar boundary (only half visible) — the whole
  /// plate must sit inside the frame, not just touch it. Kept small: on a panoramic
  /// full-car framing the plate sits low in the frame (bumper level), and a larger
  /// inset silently prevented OCR from ever running there.
  private static let ocrViewportMargin: CGFloat = 0.05
  /// Inset on the PERPENDICULAR axis (preview-horizontal = buffer Y). The viewport
  /// band only gates the buffer X axis, leaving plates flush against the LEFT/RIGHT
  /// edge of the screen readable — which produced badly-framed / half-plate captures.
  /// Require the plate to sit away from those edges too.
  private static let ocrEdgeMargin: CGFloat = 0.05
  /// Dedicated queue so OCR inference never blocks the camera/inference queues.
  private let ocrQueue = DispatchQueue(label: "yolo.infer.ocr", qos: .userInitiated)
  /// One-frame-deep back-pressure for OCR. Accessed only on cameraQueue.
  private var ocrBusy = false
  /// Pixel buffer of the frame currently in flight through the third predictor —
  /// retained so the OCR step can crop the exact frame carPart saw. cameraQueue only.
  private var thirdInFlightBuffer: CVPixelBuffer?

  // Phase-based gating (cameraQueue). Defaults match the initial framing phase:
  //   panorama/framing  → carDamage OFF, OCR ON
  //   inspection        → carDamage ON,  OCR OFF
  // carCorner (classify) and carPart (third) always run.
  private var detectEnabled = false
  private var ocrEnabled = true

  /// One-frame-deep back-pressure per predictor. Accessed only on cameraQueue.
  var detectBusy   = false
  var classifyBusy = false
  var thirdBusy    = false

  /// Classify giữ ~6–7 fps. CarPart tăng lên tối đa ~10 fps khi đang căn toàn
  /// cảnh để tạo thêm cơ hội OCR, rồi hạ về ~6–7 fps khi soi tổn thất.
  /// Accessed only on cameraQueue.
  private static let classifyMinInferenceInterval: CFTimeInterval = 0.15
  private static let thirdPanoramicMinInferenceInterval: CFTimeInterval = 0.10
  private static let thirdInspectionMinInferenceInterval: CFTimeInterval = 0.15
  private var lastClassifyTime: CFTimeInterval = 0
  private var lastThirdTime: CFTimeInterval = 0

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

  // MARK: Burst capture ring buffer (cameraQueue only)

  private static let ringCapacity = 10
  private static let postRollCount = 10
  private static let ringInterval: CFTimeInterval = 1.0
  private static let jpegEncodeContext = CIContext()

  private let ringBuffer = FrameRingBuffer(capacity: ringCapacity)
  private var stepIndex = 0
  private var lastRingWriteTime: CFTimeInterval = 0
  private var burstJpegQuality: CGFloat = 0.8

  private enum BurstState { case rolling, triggered, collecting }
  private var burstState: BurstState = .rolling
  private var burstPreRoll: [BurstFrame] = []
  private var burstPostRoll: [BurstFrame] = []
  private var burstAnchorFrame: BurstFrame?
  private var burstAnchorStepIndex: Int?
  private var pendingBurstCompletion: (([BurstFrame]) -> Void)?
  private var pendingBurstCrop: CGRect?
  private var pendingBurstQuality: CGFloat = 0.8

  // Two-phase burst (captureBurstAnchor / captureBurstAwaitPostRoll path).
  // cameraQueue only.
  private var pendingAnchorDirCompletion: (([String: Any]?) -> Void)?
  private var pendingAllFramesSplitCompletion: (([[String: Any]]?) -> Void)?
  private var burstSplitDirPath: String = ""
  /// Invalidates in-flight pre/post disk callbacks when a new burst starts or resources are released.
  private var burstEpoch: UInt64 = 0

  // MARK: Callback

  /// Called on the main thread with a stream-data dict. Keys: "type", "fps", "cameraFps",
  /// "processingTimeMs", plus task-specific keys ("detections", "classification", etc.).
  var onMultiTaskStream: (([String: Any]) -> Void)?
  /// Pre-roll and post-roll frames written to disk. Called on the main thread.
  var onSurroundingFrame: (([String: Any]) -> Void)?

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

  /// Identifies which predictor slot a result came from. Bookkeeping (busy flags, FPS) is
  /// keyed on the slot — not the task — so two detect models never clobber each other's state.
  private enum Slot { case detect, classify, third }

  private func handleResult(_ result: YOLOResult, slot: Slot) {
    let now = CACurrentMediaTime()
    let task: String
    let modelId: String
    var taskFps: Double = 0

    switch slot {
    case .detect:
      detectBusy = false
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
      classifyBusy = false
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
      thirdBusy = false
      thirdPredictor?.isUpdating = false
      if thirdLastResultTime > 0 {
        let dt = now - thirdLastResultTime
        if dt > 0 { thirdFps = 1.0 / dt }
      }
      thirdLastResultTime = now
      taskFps = thirdFps
      task = thirdTaskType
      modelId = thirdModelId
      maybeRunOCR(on: result)
    }

    let camFpsSnapshot = camFps
    let streamData = buildStreamData(
      result: result, task: task, modelId: modelId, fps: taskFps, cameraFps: camFpsSnapshot)

    DispatchQueue.main.async { [weak self] in
      self?.onMultiTaskStream?(streamData)
    }
  }

  /// If carPart found a license-plate box and OCR is idle, crop that region from
  /// the retained frame and recognize it off the camera queue. Emits a separate
  /// `type == "ocr"` stream event with `readable` used as the framing signal.
  /// Runs on cameraQueue (where `ocrBusy` / `thirdInFlightBuffer` are owned).
  private func maybeRunOCR(on result: YOLOResult) {
    guard let ocr = ocrModel, ocrEnabled, !ocrBusy, let buffer = thirdInFlightBuffer else { return }
    thirdInFlightBuffer = nil

    // Only the highest-confidence plate box that sits FULLY inside the exact
    // aspect-fill crop rect used by capturePhoto. Comparing directly with
    // ocrViewportTop/bottom is not enough because capturePhoto applies
    // aspect-fill offsets before cropping.
    let cropRect = ocrCropRectInFrame(
      frameSize: result.orig_shape,
      previewSize: previewLayer?.bounds.size ?? bounds.size)
    let loX = cropRect.minX + Self.ocrViewportMargin
    let hiX = cropRect.maxX - Self.ocrViewportMargin
    let loY = cropRect.minY + Self.ocrEdgeMargin
    let hiY = cropRect.maxY - Self.ocrEdgeMargin
    guard loX < hiX, loY < hiY else { return }
    let plateBox = result.boxes
      .filter {
        $0.cls == Self.licensePlateClass
          && $0.xywhn.minX >= loX && $0.xywhn.maxX <= hiX
          && $0.xywhn.minY >= loY && $0.xywhn.maxY <= hiY
      }
      .max { $0.conf < $1.conf }
    guard let box = plateBox else { return }

    let rect = box.xywhn  // normalized, top-left origin in the (landscape) buffer
    ocrBusy = true
    ocrQueue.async { [weak self] in
      guard let self else { return }
      let read = ocr.read(pixelBuffer: buffer, region: rect)
      let event: [String: Any] = [
        "type": "ocr",
        "modelId": "ocr",
        "plate": read?.plate ?? "",
        "score": read?.score ?? 0.0,
        "readable": read != nil,
      ]
      DispatchQueue.main.async { [weak self] in self?.onMultiTaskStream?(event) }
      self.cameraQueue.async { [weak self] in self?.ocrBusy = false }
    }
  }

  private func ocrCropRectInFrame(frameSize: CGSize, previewSize: CGSize) -> CGRect {
    let wp = frameSize.width
    let hp = frameSize.height
    let wv = previewSize.width
    let hv = previewSize.height
    guard wp > 0, hp > 0, wv > 0, hv > 0 else {
      return CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    let left: CGFloat
    let top: CGFloat
    let right: CGFloat
    let bottom: CGFloat
    if (wp >= hp) != (wv >= hv) {
      // Same mapping as capturePhoto: preview vertical band maps to frame/photo
      // horizontal coordinates after the 90° transpose.
      let s = max(wv / hp, hv / wp)
      let offU = (hp * s - wv) / 2
      let offV = (wp * s - hv) / 2
      let u0 = offU / s
      let u1 = (wv + offU) / s
      let v0 = (ocrViewportTop * hv + offV) / s
      let v1 = (ocrViewportBottom * hv + offV) / s
      left = v0
      right = v1
      top = hp - u1
      bottom = hp - u0
    } else {
      let s = max(wv / wp, hv / hp)
      let offX = (wp * s - wv) / 2
      let offY = (hp * s - hv) / 2
      left = offX / s
      right = (wv + offX) / s
      top = (ocrViewportTop * hv + offY) / s
      bottom = (ocrViewportBottom * hv + offY) / s
    }

    let l = min(max(left / wp, 0), 1)
    let r = min(max(right / wp, 0), 1)
    let t = min(max(top / hp, 0), 1)
    let b = min(max(bottom / hp, 0), 1)
    return CGRect(
      x: min(l, r),
      y: min(t, b),
      width: abs(r - l),
      height: abs(b - t))
  }

  /// Updates the visible viewport used to gate OCR (preview-space vertical band).
  func setOcrViewport(top: CGFloat, bottom: CGFloat) {
    cameraQueue.async { [weak self] in
      self?.ocrViewportTop = top
      self?.ocrViewportBottom = bottom
    }
  }

  /// Phase-based gating: inspection runs carDamage and stops OCR; framing/panorama
  /// runs OCR and stops carDamage. carCorner/carPart always run.
  func setInspectionActive(_ active: Bool) {
    cameraQueue.async { [weak self] in
      self?.detectEnabled = active
      self?.ocrEnabled = !active
    }
  }

  // MARK: - Stream data builder

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

    // OCR is not a YOLO predictor and must not gate camera start — load it on a
    // background queue and attach when ready (frames before that simply skip OCR).
    if let ocrPath = ocrModelPath, let ocrURL = resolveModelURL(ocrPath) {
      DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let ocr = LicensePlateOCR(modelURL: ocrURL, threshold: ocrConfidenceThreshold)
        DispatchQueue.main.async {
          self?.ocrModel = ocr
          NSLog(ocr == nil
            ? "YOLOMultiTaskView: ⚠️ OCR model failed to load"
            : "YOLOMultiTaskView: ✅ OCR model loaded")
        }
      }
    }

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
    }

    captureSession.startRunning()
    camFpsWindowStart = CACurrentMediaTime()
    stepIndex = 0
    lastRingWriteTime = 0
    burstState = .rolling
    burstPreRoll = []
    burstPostRoll = []
    burstAnchorFrame = nil
    burstAnchorStepIndex = nil
    pendingBurstCompletion = nil
  }

  // MARK: - Burst capture

  public func captureBurst(
    crop: CGRect? = nil,
    quality: CGFloat = 0.8,
    completion: @escaping ([BurstFrame]) -> Void
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        completion([])
        return
      }
      let previewSize = self.bounds.size
      self.cameraQueue.async { [weak self] in
        guard let self else {
          DispatchQueue.main.async { completion([]) }
          return
        }
        self.startBurstCapture(
          crop: crop,
          previewSize: previewSize,
          quality: quality,
          completion: completion
        )
      }
    }
  }

  public func captureBurstToFiles(
    dirPath: String,
    crop: CGRect? = nil,
    quality: CGFloat = 0.8,
    completion: @escaping ([[String: Any]]?) -> Void
  ) {
    captureBurst(crop: crop, quality: quality) { frames in
      guard !frames.isEmpty else {
        completion(nil)
        return
      }
      DispatchQueue.global(qos: .utility).async {
        do {
          try FileManager.default.createDirectory(
            atPath: dirPath,
            withIntermediateDirectories: true
          )
          var maps: [[String: Any]] = []
          for frame in frames {
            let path = (dirPath as NSString).appendingPathComponent("\(frame.stepIndex).jpg")
            try frame.data.write(to: URL(fileURLWithPath: path), options: .atomic)
            maps.append([
              "filePath": path,
              "stepIndex": frame.stepIndex,
              "isCallEngine": frame.isCallEngine,
            ])
          }
          DispatchQueue.main.async { completion(maps) }
        } catch {
          NSLog(
            "YOLOMultiTaskView: captureBurstToFiles failed: %@",
            error.localizedDescription
          )
          DispatchQueue.main.async { completion(nil) }
        }
      }
    }
  }

  private func startBurstCapture(
    crop: CGRect?,
    previewSize: CGSize,
    quality: CGFloat,
    completion: @escaping ([BurstFrame]) -> Void
  ) {
    deliverInFlightBurstIfNeeded()

    pendingBurstCompletion = completion
    pendingBurstCrop = crop
    pendingBurstQuality = quality
    pendingPreviewSize = previewSize
    burstJpegQuality = quality

    burstPreRoll = ringBuffer.snapshot()
    burstPostRoll = []
    burstAnchorFrame = nil
    let anchorIdx = stepIndex
    stepIndex += 1
    burstAnchorStepIndex = anchorIdx
    burstState = .triggered
    lastRingWriteTime = CACurrentMediaTime()

    let settings = AVCapturePhotoSettings()
    settings.flashMode = .off
    photoOutput.capturePhoto(with: settings, delegate: self)
  }

  /// Two-phase burst entry point. Triggers anchor capture and calls `onAnchorReady`
  /// as soon as the single anchor JPEG is written to disk (~200ms). Pre-roll frames
  /// are persisted in parallel from T=0 via `onSurroundingFrame`; post-roll streams
  /// the same way. `onAllReady` is optional (nil = skip batch write in finalize).
  public func startBurstForCapture(
    dirPath: String,
    crop: CGRect?,
    quality: CGFloat,
    onAnchorReady: @escaping ([String: Any]?) -> Void,
    onAllReady: (([[String: Any]]?) -> Void)? = nil
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        onAnchorReady(nil)
        return
      }
      let previewSize = self.bounds.size
      self.cameraQueue.async { [weak self] in
        guard let self else {
          DispatchQueue.main.async { onAnchorReady(nil) }
          return
        }
        self.deliverInFlightBurstIfNeeded()
        self.burstEpoch += 1
        let epoch = self.burstEpoch

        self.burstSplitDirPath = dirPath
        self.pendingBurstCrop = crop
        self.pendingBurstQuality = quality
        self.pendingPreviewSize = previewSize
        self.burstJpegQuality = quality

        self.burstPreRoll = self.ringBuffer.snapshot()
        self.persistPreRollFrames(self.burstPreRoll, dirPath: dirPath, epoch: epoch)
        self.burstPostRoll = []
        self.burstAnchorFrame = nil
        let anchorIdx = self.stepIndex
        self.stepIndex += 1
        self.burstAnchorStepIndex = anchorIdx
        self.burstState = .triggered
        self.lastRingWriteTime = CACurrentMediaTime()

        self.pendingAnchorDirCompletion = onAnchorReady
        self.pendingAllFramesSplitCompletion = onAllReady

        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        self.photoOutput.capturePhoto(with: settings, delegate: self)
      }
    }
  }

  private func deliverInFlightBurstIfNeeded() {
    let hasPendingSingle = pendingBurstCompletion != nil
    let hasPendingSplit = pendingAnchorDirCompletion != nil || pendingAllFramesSplitCompletion != nil
    guard hasPendingSingle || hasPendingSplit else { return }
    burstEpoch += 1

    let completion = pendingBurstCompletion
    pendingBurstCompletion = nil
    let anchorCallback = pendingAnchorDirCompletion
    pendingAnchorDirCompletion = nil
    let allCallback = pendingAllFramesSplitCompletion
    pendingAllFramesSplitCompletion = nil

    var frames = burstPreRoll
    if let anchor = burstAnchorFrame { frames.append(anchor) }
    frames.append(contentsOf: burstPostRoll)
    frames.sort { $0.stepIndex < $1.stepIndex }
    burstState = .rolling
    burstPreRoll = []
    burstPostRoll = []
    burstAnchorFrame = nil
    burstAnchorStepIndex = nil

    if let completion {
      DispatchQueue.main.async { completion(frames) }
    }
    // Split path: deliver nil (burst aborted by new trigger)
    if let anchorCallback {
      DispatchQueue.main.async { anchorCallback(nil) }
    }
    if let allCallback {
      DispatchQueue.main.async { allCallback(nil) }
    }
  }

  private func handleBurstAnchorPhoto(_ data: Data?) {
    guard burstState == .triggered, let anchorIdx = burstAnchorStepIndex else { return }
    if let data {
      burstAnchorFrame = BurstFrame(data: data, stepIndex: anchorIdx, isCallEngine: true)

      // Two-phase path: write anchor to disk immediately and call early callback so
      // the Dart side can start the freeze overlay without waiting for post-roll.
      if let anchorCallback = pendingAnchorDirCompletion {
        pendingAnchorDirCompletion = nil
        let dirPath = burstSplitDirPath
        let anchorData = data  // already processed (cropped, oriented) JPEG
        DispatchQueue.global(qos: .utility).async { [weak self] in
          guard self != nil else { return }
          do {
            try FileManager.default.createDirectory(
              atPath: dirPath, withIntermediateDirectories: true)
            let path = (dirPath as NSString).appendingPathComponent("\(anchorIdx).jpg")
            try anchorData.write(to: URL(fileURLWithPath: path), options: .atomic)
            let map: [String: Any] = [
              "filePath": path,
              "stepIndex": anchorIdx,
              "isCallEngine": true,
            ]
            DispatchQueue.main.async { anchorCallback(map) }
          } catch {
            NSLog(
              "YOLOMultiTaskView: anchor write failed: %@",
              error.localizedDescription)
            DispatchQueue.main.async { anchorCallback(nil) }
          }
        }
      }

      burstState = .collecting
      lastRingWriteTime = CACurrentMediaTime()
      if burstPostRoll.count >= Self.postRollCount {
        finalizeBurst()
      }
    } else {
      // Anchor capture failed — clear split anchor callback too.
      pendingAnchorDirCompletion = nil
      finalizeBurst()
    }
  }

  private func finalizeBurst() {
    let completion = pendingBurstCompletion
    let allCallback = pendingAllFramesSplitCompletion
    pendingBurstCompletion = nil
    pendingAllFramesSplitCompletion = nil
    burstState = .rolling

    var frames = burstPreRoll
    if let anchor = burstAnchorFrame { frames.append(anchor) }
    frames.append(contentsOf: burstPostRoll)
    frames.sort { $0.stepIndex < $1.stepIndex }

    burstPreRoll = []
    burstPostRoll = []
    burstAnchorFrame = nil
    burstAnchorStepIndex = nil

    // Legacy single-call path (existing captureBurst flow).
    if let completion {
      DispatchQueue.main.async { completion(frames) }
      return
    }

    // Two-phase path: write pre-roll/post-roll to disk (anchor already written)
    // and deliver all frame maps to Dart.
    if let allCallback {
      let dirPath = burstSplitDirPath
      DispatchQueue.global(qos: .utility).async {
        do {
          var maps: [[String: Any]] = []
          for frame in frames {
            let path = (dirPath as NSString).appendingPathComponent("\(frame.stepIndex).jpg")
            if !frame.isCallEngine {
              // Pre/post-roll frames: write to disk now.
              try frame.data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
            // Anchor already written by handleBurstAnchorPhoto; include path only.
            maps.append([
              "filePath": path,
              "stepIndex": frame.stepIndex,
              "isCallEngine": frame.isCallEngine,
            ])
          }
          DispatchQueue.main.async { allCallback(maps) }
        } catch {
          NSLog(
            "YOLOMultiTaskView: burst split frames write failed: %@",
            error.localizedDescription)
          DispatchQueue.main.async { allCallback(nil) }
        }
      }
    }
    // If neither callback is set, burst was aborted — state already cleaned up.
  }

  private func sampleRingBuffer(from sampleBuffer: CMSampleBuffer, quality: CGFloat) {
    let idx = stepIndex
    stepIndex += 1
    let buf = sampleBuffer
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(buf),
        let jpegData = Self.encodeJPEG(from: pixelBuffer, quality: quality)
      else { return }
      let frame = BurstFrame(data: jpegData, stepIndex: idx, isCallEngine: false)
      self?.cameraQueue.async { [weak self] in
        self?.ringBuffer.write(frame)
      }
    }
  }

  private func persistPreRollFrames(_ frames: [BurstFrame], dirPath: String, epoch: UInt64) {
    guard !frames.isEmpty else { return }
    DispatchQueue.global(qos: .utility).async { [weak self] in
      try? FileManager.default.createDirectory(
        atPath: dirPath, withIntermediateDirectories: true)
      for frame in frames {
        let path = (dirPath as NSString).appendingPathComponent("\(frame.stepIndex).jpg")
        try? frame.data.write(to: URL(fileURLWithPath: path), options: .atomic)
        let frameMap: [String: Any] = [
          "filePath": path,
          "stepIndex": frame.stepIndex,
          "isCallEngine": false,
          "isPostRoll": false,
        ]
        self?.cameraQueue.async { [weak self] in
          guard let self, self.burstEpoch == epoch else { return }
          let cb = self.onSurroundingFrame
          DispatchQueue.main.async { cb?(frameMap) }
        }
      }
    }
  }

  private func collectPostRollFrame(from sampleBuffer: CMSampleBuffer, quality: CGFloat) {
    let idx = stepIndex
    stepIndex += 1
    let buf = sampleBuffer
    let dirPath = burstSplitDirPath
    let epoch = burstEpoch
    DispatchQueue.global(qos: .utility).async { [weak self] in
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(buf),
        let jpegData = Self.encodeJPEG(from: pixelBuffer, quality: quality)
      else { return }
      let path = (dirPath as NSString).appendingPathComponent("\(idx).jpg")
      try? jpegData.write(to: URL(fileURLWithPath: path), options: .atomic)
      let frameMap: [String: Any] = [
        "filePath": path,
        "stepIndex": idx,
        "isCallEngine": false,
        "isPostRoll": true,
      ]
      let frame = BurstFrame(data: jpegData, stepIndex: idx, isCallEngine: false)
      self?.cameraQueue.async { [weak self] in
        guard let self else { return }
        guard self.burstEpoch == epoch, self.burstState == .collecting else { return }
        self.burstPostRoll.append(frame)
        let cb = self.onSurroundingFrame
        DispatchQueue.main.async { cb?(frameMap) }
        if self.burstPostRoll.count >= Self.postRollCount {
          self.finalizeBurst()
        }
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

  private func processPhotoJPEG(
    data: Data,
    crop: CGRect?,
    previewSize: CGSize,
    quality: CGFloat
  ) -> Data? {
    guard let src = UIImage(data: data) else { return data }
    if crop == nil, src.imageOrientation == .up { return data }

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
      return upright.jpegData(compressionQuality: quality)
    }

    let wp = CGFloat(cg.width), hp = CGFloat(cg.height)
    let wv = previewSize.width, hv = previewSize.height
    let rect: CGRect
    if (wp >= hp) != (wv >= hv) {
      let s = max(wv / hp, hv / wp)
      let offU = (hp * s - wv) / 2
      let offV = (wp * s - hv) / 2
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
      return upright.jpegData(compressionQuality: quality)
    }
    return UIImage(cgImage: cropped).jpegData(compressionQuality: quality)
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
      self?.captureSession.stopRunning()
    }
  }

  /// Full resource release: stops camera, removes preview layer, nils predictors and callback.
  /// Call from the platform view's dispose/deinit path so GPU/ANE memory is freed promptly
  /// even if deinit is delayed by a retain cycle in the Flutter EventChannel stream handler.
  public func releaseResources() {
    onMultiTaskStream = nil
    onSurroundingFrame = nil
    cameraQueue.async { [weak self] in
      guard let self else { return }
      self.burstEpoch += 1
      self.captureSession.stopRunning()
      self.pendingBurstCompletion = nil
      self.pendingAnchorDirCompletion = nil
      self.pendingAllFramesSplitCompletion = nil
      self.burstState = .rolling
      self.burstPreRoll = []
      self.burstPostRoll = []
      self.burstAnchorFrame = nil
      self.burstAnchorStepIndex = nil
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
    ocrModel = nil
    thirdInFlightBuffer = nil
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

    // Dispatch each predictor to its own queue so all run concurrently.
    // carDamage is skipped (input blocked) during the framing/panorama phase.
    if let p = detectPredictor, detectEnabled, !detectBusy, !p.isUpdating {
      detectBusy = true
      p.isUpdating = true
      let buf = sampleBuffer
      let adapter = detectAdapter
      detectQueue.async { p.predict(sampleBuffer: buf, onResultsListener: adapter, onInferenceTime: adapter) }
    }
    if let p = classifyPredictor, !classifyBusy, !p.isUpdating,
      now - lastClassifyTime >= Self.classifyMinInferenceInterval
    {
      lastClassifyTime = now
      classifyBusy = true
      p.isUpdating = true
      let buf = sampleBuffer
      let adapter = classifyAdapter
      classifyQueue.async { p.predict(sampleBuffer: buf, onResultsListener: adapter, onInferenceTime: adapter) }
    }
    let thirdMinInterval = ocrEnabled
      ? Self.thirdPanoramicMinInferenceInterval
      : Self.thirdInspectionMinInferenceInterval
    if let p = thirdPredictor, !thirdBusy, !p.isUpdating,
      now - lastThirdTime >= thirdMinInterval
    {
      lastThirdTime = now
      thirdBusy = true
      p.isUpdating = true
      let buf = sampleBuffer
      let adapter = thirdAdapter
      // Retain this frame's pixel buffer so the OCR step (run from the third
      // result handler) can crop the exact frame carPart processed. Skipped when
      // OCR is gated off (inspection phase).
      if ocrModel != nil, ocrEnabled {
        thirdInFlightBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
      }
      thirdQueue.async { p.predict(sampleBuffer: buf, onResultsListener: adapter, onInferenceTime: adapter) }
    }

    // Burst ring buffer (0.5s cadence) and post-roll collection.
    if burstState == .rolling,
      now - lastRingWriteTime >= Self.ringInterval
    {
      lastRingWriteTime = now
      sampleRingBuffer(from: sampleBuffer, quality: burstJpegQuality)
    } else if burstState == .collecting,
      now - lastRingWriteTime >= Self.ringInterval
    {
      lastRingWriteTime = now
      collectPostRollFrame(from: sampleBuffer, quality: pendingBurstQuality)
    }
  }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension YOLOMultiTaskView: AVCapturePhotoCaptureDelegate {
  public func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    let singleCompletion = photoCaptureCompletion
    photoCaptureCompletion = nil

    let cropForBurst = pendingBurstCrop
    let qualityForBurst = pendingBurstQuality
    let previewSize = pendingPreviewSize
    let quality = pendingJpegQuality
    let crop = pendingCrop
    pendingCrop = nil
    pendingBurstCrop = nil

    guard error == nil, let rawData = photo.fileDataRepresentation() else {
      if burstState == .triggered {
        handleBurstAnchorPhoto(nil)
      } else {
        singleCompletion?(nil)
      }
      return
    }

    if burstState == .triggered {
      let jpeg = processPhotoJPEG(
        data: rawData,
        crop: cropForBurst,
        previewSize: previewSize,
        quality: qualityForBurst
      )
      handleBurstAnchorPhoto(jpeg)
      return
    }

    let jpeg = processPhotoJPEG(
      data: rawData,
      crop: crop,
      previewSize: previewSize,
      quality: quality
    )
    singleCompletion?(jpeg)
  }
}
