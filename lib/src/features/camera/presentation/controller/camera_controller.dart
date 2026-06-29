import 'dart:async';

import '../../../../yolo/multi_task_yolo_view.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/cache/photo_session_cache.dart';
import '../../../../core/constants/string_sheet.dart';
import '../../data/model/camera_message.dart';
import '../../data/model/car_angle.dart';
import '../../data/model/classify_output.dart';
import '../../data/model/detection_output.dart';

/// Sub-states of the damage inspection flow (active when panoramic photo is taken).
enum InspectionPhase {
  /// Initial message: "Đưa camera lại gần tổn thất…" — X → scanning, Chuyển góc → done.
  panoramicGuide,

  /// Scanning for damage. Detection is event-driven: ngay khi có detection
  /// → detectionReady. Sau 10 s không có detection → warning.
  scanning,

  /// Detections found — showing "Xác nhận / Thiếu tổn thất". Sau 5 s không
  /// bấm gì sẽ tự động chụp.
  detectionReady,

  /// Đang chụp ảnh tổn thất (tự động hoặc do bấm "Xác nhận").
  capturingDamage,

  /// Hiển thị message "Tiếp tục di chuyển camera…" trong 5 s rồi quay lại
  /// scanning.
  continueOrChange,
}

class CameraController extends ChangeNotifier {
  CameraController({required String sessionId}) : _sessionId = sessionId;

  final String _sessionId;
  final yoloController = MultiTaskYOLOController();

  bool _torchEnabled = false;
  bool _isCapturing = false;

  /// User chưa bấm "Bắt đầu chụp ảnh xe" (guide sheet) → tạm bỏ qua mọi output
  /// streaming từ YOLO. Bật lên qua [startCapture].
  bool _captureStarted = false;

  Map<int, List<Uint8List>> _capturedPhotos = {};

  /// Vùng camera user thực sự nhìn thấy (giữa top bar và bottom bar), dạng tỉ lệ
  /// [0,1] theo chiều dọc của preview. Dùng để native crop ảnh chụp về đúng
  /// khung nhìn (preview là aspect-fill nên ảnh gốc rộng/cao hơn vùng thấy).
  double _cropTop = 0;
  double _cropBottom = 1;

  /// Viewport đã gửi xuống native (để gate OCR). Null khi chưa gửi thành công —
  /// platform view có thể chưa attach ở lần layout đầu, nên thử lại tới khi gửi được.
  double? _sentCropTop;
  double? _sentCropBottom;

  /// Bumped every time a photo is actually captured — the view listens to
  /// this to trigger a screen-blink (flash) effect.
  int _captureFlashTick = 0;
  CameraMessage? _message;

  /// Segment index (0–3) đang được detect, null nếu chưa nhận kết quả.
  /// Đây là góc cho LUỒNG xử lý (bị khoá khi [_classificationLocked]).
  int? _activeSegmentIndex;

  /// Góc (0–3) đang được classify nhận diện trực tiếp ở frame mới nhất — luôn
  /// cập nhật bất kể flow có khoá hay không, dùng để highlight trên UI.
  int? _detectedSegmentIndex;

  /// Angles that have a panoramic photo (inspection started but not completed).
  final Set<int> _panoramicCapturedSegments = {};

  /// When true, classify frames are ignored to lock the current angle.
  bool _classificationLocked = false;

  /// Angles fully completed (user pressed "Chuyển góc").
  final Set<int> _completedSegments = {};

  /// Tên class biển số xe trong model car-part (khớp với logic native OCR).
  static const _licensePlateClass = 'Biển số xe';

  /// Class names bộ phận từ frame car-part detect (model thứ 2) mới nhất.
  Set<String> _latestCarPartClasses = {};

  /// OCR (native) đọc được biển số ở frame mới nhất hay chưa. Là tín hiệu canh
  /// khung: đọc được biển ⇒ khung đủ rõ/đủ gần để dùng làm ảnh toàn cảnh.
  bool _latestPlateReadable = false;

  /// Chi tiết bộ phận (kèm bounding box) từ frame car-part detect mới nhất —
  /// dùng để vẽ nhãn tên bộ phận lên màn hình.
  List<DetectionResult> _latestCarPartDetections = [];

  /// Detections từ frame detect mới nhất.
  List<DetectionResult> _latestDetections = [];

  /// Current phase of the damage inspection sub-flow. null = not in inspection.
  InspectionPhase? _inspectionPhase;

  /// 5s timer chạy ở detectionReady: hết 5s mà user không bấm gì thì tự
  /// động chụp ảnh tổn thất.
  Timer? _autoCaptureTimer;

  /// One-shot timer: if no damage is detected within 10 s of unlocking
  /// detection (right after the panoramic photo is taken), the current
  /// angle is auto-completed.
  Timer? _noDetectionTimer;

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isTorchEnabled => _torchEnabled;
  bool get isCapturing => _isCapturing;
  Map<int, List<Uint8List>> get capturedPhotos => _capturedPhotos;
  int? get activeSegmentIndex => _detectedSegmentIndex ?? _activeSegmentIndex;
  Set<int> get completedSegments => Set.unmodifiable(_completedSegments);
  CameraMessage? get message => _message;
  int get captureFlashTick => _captureFlashTick;
  List<DetectionResult> get latestDetections => _latestDetections;
  List<DetectionResult> get latestCarPartDetections => _latestCarPartDetections;
  InspectionPhase? get inspectionPhase => _inspectionPhase;

  /// True when actively inspecting for damage (panoramic already taken).
  bool get isInspectionMode => _inspectionPhase != null;

  /// Bounding boxes are shown only during inspection (after panoramic).
  bool get showBoundingBoxes => _inspectionPhase != null;

  /// Cập nhật khung nhìn thấy (do view tính từ chiều cao top/bottom bar so với
  /// chiều cao preview). Ảnh chụp sẽ được crop về đúng khung này.
  void setCaptureViewport({required double top, required double bottom}) {
    _cropTop = top;
    _cropBottom = bottom;
    // Gửi viewport xuống native để gate OCR (chỉ đọc biển nằm trọn trong khung
    // nhìn thấy). Gọi mỗi lần layout; chỉ gửi khi đổi hoặc lần trước chưa gửi
    // được (platform view có thể chưa attach ở layout đầu).
    if (_sentCropTop != top || _sentCropBottom != bottom) {
      if (yoloController.setViewport(top, bottom)) {
        _sentCropTop = top;
        _sentCropBottom = bottom;
      }
    }
  }

  /// Lọc các detection chỉ giữ lại box nằm trong khung nhìn thực sự (dải giữa
  /// top/bottom bar). Camera frame là landscape, preview xoay 90° để hiển thị
  /// dọc nên trục dọc màn hình (nơi 2 bar che) tương ứng với trục X của box
  /// (`centerX`). Khung nhìn theo trục đó là `[_cropTop, _cropBottom]`.
  /// `(0,1)` = không che → trả nguyên danh sách.
  List<DetectionResult> _filterToViewport(List<DetectionResult> detections) {
    if (_cropTop <= 0 && _cropBottom >= 1) return detections;
    return detections
        .where((d) =>
            d.normalizedBox.centerX >= _cropTop &&
            d.normalizedBox.centerX <= _cropBottom)
        .toList();
  }

  // ── Cache restore ─────────────────────────────────────────────────────────

  /// Restores previously captured photos from disk cache.
  /// Call once after construction; notifies listeners when done.
  Future<void> loadCachedPhotos() async {
    final cached = await PhotoSessionCache.instance.loadSession(_sessionId);
    if (cached.isEmpty) return;
    _capturedPhotos = cached;
    // Angles with cached photos are shown as completed in the progress ring.
    _completedSegments.addAll(cached.keys);
    notifyListeners();
  }

  // ── Capture gate ──────────────────────────────────────────────────────────

  /// Gọi khi user bấm "Bắt đầu chụp ảnh xe" ở guide sheet — mở cổng cho phép
  /// [onStreamingData] bắt đầu xử lý frame. An toàn khi gọi nhiều lần.
  void startCapture() => _captureStarted = true;

  // ── Streaming data ────────────────────────────────────────────────────────

  // [data] đã là Map<String, dynamic> do MultiTaskYOLOView cấp — dùng trực tiếp,
  // không copy lại (mỗi frame chạy trên UI thread). Mỗi nhánh chỉ
  // notifyListeners() đúng một lần và chỉ khi có thay đổi nhìn thấy được, để
  // tránh rebuild thừa khi stream bắn nhiều frame/giây.
  void onStreamingData(Map<String, dynamic> data) {
    // User chưa bấm "Bắt đầu chụp ảnh xe" → bỏ qua toàn bộ frame streaming.
    if (!_captureStarted) return;

    final type = data['type'];
    // Hai model detect đều trả type=='detect'; phân biệt bằng modelId:
    //   'detect'  -> car damage (model chính)
    //   'detect2' -> car part   (model thứ 2)
    final modelId = data['modelId'];
    if (type == 'classify') {
      // carCorner — phân loại góc xe.
      final output = ClassifyOutput.fromJson(data);
      final segment = CarAngle.segmentOf(output.classification.top1);
      // Luôn highlight góc đang nhận diện được, kể cả khi flow đã khoá.
      final highlightChanged =
          segment != null && segment != _detectedSegmentIndex;
      if (highlightChanged) _detectedSegmentIndex = segment;

      // Cập nhật luồng (chỉ khi chưa khoá và góc đổi). Các hàm bên trong
      // (startDamageScanning/updateMessage) tự notify khi message đổi.
      if (!_classificationLocked && segment != _activeSegmentIndex) {
        _activeSegmentIndex = segment;
        // Góc này đã có ảnh toàn cảnh → bắt đầu luôn từ scanning, không cần
        // chụp toàn cảnh lại.
        if (_panoramicCapturedSegments.contains(segment)) {
          _classificationLocked = true;
          startDamageScanning();
        } else {
          updateMessage();
        }
      }
      if (highlightChanged) notifyListeners();
      return;
    }

    if (type == 'ocr') {
      // OCR (native) — tín hiệu canh khung. Đọc được biển ⇒ frame đủ tốt để
      // làm ảnh toàn cảnh; cập nhật cờ rồi re-evaluate để có thể kích hoạt chụp.
      final readable = data['readable'] == true;
      if (readable != _latestPlateReadable) {
        _latestPlateReadable = readable;
        if (readable) updateMessage(); // tự notify khi message đổi
      }
      return;
    }

    if (type == 'detect' && modelId == 'detect2') {
      // carPart — model detect bộ phận, dùng để căn ảnh toàn cảnh.
      final output = DetectionOutput.fromJson(data);
      final wasEmpty = _latestCarPartDetections.isEmpty;
      // Chỉ giữ bộ phận nằm trong vùng user thực sự nhìn thấy (giữa top/bottom
      // bar) — model xử lý cả phần bị che nên phải lọc lại.
      final visible = _filterToViewport(output.detections);
      _latestCarPartClasses = visible.map((d) => d.className).toSet();
      _latestCarPartDetections = visible;
      // Biển không còn trong khung → cờ "đọc được" cũ không còn hiệu lực.
      if (!_latestCarPartClasses.contains(_licensePlateClass)) {
        _latestPlateReadable = false;
      }
      updateMessage(); // tự notify khi message đổi
      // Bỏ qua redraw nếu không có nhãn bộ phận nào để vẽ (trước & sau đều rỗng).
      if (!(wasEmpty && visible.isEmpty)) notifyListeners();
      return;
    }

    if (type == 'detect') {
      // carDamage — model detect tổn thất (model chính).
      final output = DetectionOutput.fromJson(data);
      // Bỏ qua tổn thất nằm ngoài khung nhìn (bị top/bottom bar che).
      _latestDetections = _filterToViewport(output.detections);
      // Phát hiện tổn thất → hiển thị xác nhận ngay, không chờ timer 5s.
      _maybeShowDetectionReady(); // tự notify khi chuyển pha
      // Bounding box chỉ vẽ khi đang trong pha inspection; ngoài ra việc đổi
      // _latestDetections không ảnh hưởng UI → khỏi rebuild.
      if (showBoundingBoxes) notifyListeners();
    }
  }

  // ── Torch ─────────────────────────────────────────────────────────────────

  Future<void> toggleFlash() async {
    final actual = await yoloController.setTorch(!_torchEnabled);
    _torchEnabled = actual;
    notifyListeners();
  }

  // ── Photo capture ─────────────────────────────────────────────────────────

  /// Captures a JPEG frame, stores it in memory and on disk.
  /// Does NOT modify [_completedSegments] — completion is via [completeCurrentAngle].
  Future<Uint8List?> capturePhoto({
    bool immediate = false,
    int? segment,
    bool flashTick = true,
  }) async {
    if (_isCapturing) return null;
    _isCapturing = true;
    notifyListeners();
    try {
      /// Chụp tự động quá nhanh, người dùng chưa kịp đọc message -> delay 3s.
      /// Chụp thủ công ([immediate]) thì chụp ngay.
      if (!immediate) await Future.delayed(const Duration(seconds: 3));
      if (flashTick) {
        _captureFlashTick++;
      }

      final bytes = await yoloController.capturePhoto(
        cropTop: _cropTop,
        cropBottom: _cropBottom,
      );
      final seg = segment ?? _activeSegmentIndex;
      if (seg != null) {
        _capturedPhotos.putIfAbsent(seg, () => []).add(bytes);
        PhotoSessionCache.instance.savePhoto(_sessionId, seg, bytes);
      }
      notifyListeners();
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _isCapturing = false;
      notifyListeners();
    }
  }

  /// Chụp thủ công bằng nút shutter: chụp ngay, lưu vào góc đang active (mặc
  /// định góc 0 nếu chưa phân loại được góc).
  Future<void> manualCapture() =>
      capturePhoto(immediate: true, segment: _activeSegmentIndex ?? 0);

  // ── Panoramic message logic ───────────────────────────────────────────────

  static const _segmentConfigs = {
    0: ('Ba đờ sốc trước', StringSheet.frontRightGuide),
    1: ('Ba đờ sốc sau', StringSheet.backRightGuide),
    2: ('Ba đờ sốc sau', StringSheet.backLeftGuide),
    3: ('Ba đờ sốc trước', StringSheet.frontLeftGuide),
  };

  Future<void> updateMessage() async {
    if (_activeSegmentIndex == null) {
      _setMessage(null);
      return;
    }
    if (_completedSegments.contains(_activeSegmentIndex)) return;
    if (_panoramicCapturedSegments.contains(_activeSegmentIndex)) return;
    if (_isCapturing) return;
    _updateMessageSegment(_latestCarPartClasses, _activeSegmentIndex!);
  }

  void clearMessage() => _setMessage(null);

  void _updateMessageSegment(Set<String> classes, int segmentIndex) {
    const licencePlate = _licensePlateClass;
    const door = 'Cánh cửa';

    final config = _segmentConfigs[segmentIndex];
    if (config == null) return;

    final (frontBumper, initialGuide) = config;

    if (!classes.contains(licencePlate)) {
      _setMessage(
          CameraMessage(message: initialGuide, type: MessageType.guide));
    } else if (!classes.contains(door)) {
      _setMessage(CameraMessage(
          message: StringSheet.moveBackGuide, type: MessageType.info));
    } else if (classes.contains(door) &&
        classes.contains(frontBumper) &&
        classes.contains(licencePlate)) {
      // Bộ phận đã căn đủ — giữ yên để OCR đọc biển số. Chỉ chụp ảnh toàn cảnh
      // khi OCR đọc được biển (khung đủ rõ/đủ gần), tránh chụp ảnh mờ/xa.
      _setMessage(CameraMessage(
          message: StringSheet.holdStillGuide, type: MessageType.loading));
      if (_latestPlateReadable) {
        _triggerAutoCapture();
      }
    }
  }

  Future<void> _triggerAutoCapture() async {
    // Cờ "đọc được biển" chỉ dùng cho 1 lần chụp toàn cảnh; reset để góc sau
    // phải đọc lại biển mới chụp.
    _latestPlateReadable = false;
    // OCR vừa đọc được biển ở frame hiện tại ⇒ chụp NGAY (immediate, bỏ delay 3s)
    // để ảnh toàn cảnh sát nhất với frame đã canh đúng khung + đọc được biển.
    await capturePhoto(immediate: true);
    if (_activeSegmentIndex != null) {
      _panoramicCapturedSegments.add(_activeSegmentIndex!);
      // Chụp toàn cảnh xong là góc đó đã được tính hoàn thành.
      _completedSegments.add(_activeSegmentIndex!);
    }
    _classificationLocked = true;
    _setInspectionPhase(InspectionPhase.panoramicGuide);
    _setMessage(CameraMessage(
      message: StringSheet.inspectDamageGuide,
      type: MessageType.info,
    ));
    // Đang hướng dẫn soi tổn thất: nếu sau 10 s vẫn không phát hiện tổn thất
    // → cảnh báo rồi tự chuyển góc.
    _startNoDetectionTimer();
  }

  // ── Inspection / damage flow ──────────────────────────────────────────────

  /// Bắt đầu (hoặc quay lại) trạng thái scanning: detection chạy theo sự kiện,
  /// đồng thời mở 10 s no-detection timeout.
  void startDamageScanning() => _enterScanning();

  void _enterScanning() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    // Vào pha quét thiệt hại → bật carDamage (carCorner/carPart vẫn bật).
    _setInspectionPhase(InspectionPhase.scanning);
    _setMessage(null);
    _startNoDetectionTimer();
  }

  /// Khi đang quét mà phát hiện tổn thất → hiển thị xác nhận ngay lập tức.
  /// An toàn khi gọi nhiều lần.
  void _maybeShowDetectionReady() {
    if (_latestDetections.isEmpty) return;

    // Vừa chụp toàn cảnh xong (đang ở màn hướng dẫn) mà đã phát hiện tổn thất
    // → vào scanning luôn, không cần user bấm X / Chuyển góc.
    if (_inspectionPhase == InspectionPhase.panoramicGuide) {
      _enterScanning();
    }

    if (_inspectionPhase != InspectionPhase.scanning) return;

    _noDetectionTimer?.cancel();
    _noDetectionTimer = null;
    // Đã thấy thiệt hại, chờ user xác nhận.
    _setInspectionPhase(InspectionPhase.detectionReady);
    _setMessage(CameraMessage(
      message: StringSheet.damageDetectedGuide,
      type: MessageType.info,
    ));
    // Sau 5 s không bấm gì → tự động chụp.
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = Timer(const Duration(seconds: 5), () {
      if (_inspectionPhase == InspectionPhase.detectionReady) {
        confirmDamage(flashTick: false);
      }
    });
  }

  /// Các pha đang chờ phát hiện tổn thất: hướng dẫn soi (panoramicGuide) và
  /// đang quét (scanning). Hết 10 s mà không thấy tổn thất → cảnh báo rồi rời góc.
  bool get _isAwaitingDamage =>
      _inspectionPhase == InspectionPhase.scanning ||
      _inspectionPhase == InspectionPhase.panoramicGuide;

  /// 10 s không phát hiện tổn thất → cảnh báo rồi rời góc.
  void _startNoDetectionTimer() {
    _noDetectionTimer?.cancel();
    _noDetectionTimer =
        Timer(const Duration(seconds: 10), _onNoDetectionTimeout);
  }

  Future<void> _onNoDetectionTimeout() async {
    if (!_isAwaitingDamage) return;
    if (_latestDetections.isNotEmpty) return;

    _setMessage(CameraMessage(
      message: StringSheet.noDamageDetectedGuide,
      type: MessageType.warning,
    ));

    await Future.delayed(const Duration(seconds: 5));
    // Guard: angle may already have been completed/changed during the delay.
    if (!_isAwaitingDamage) return;
    completeCurrentAngle();
  }

  /// User pressed "Thiếu tổn thất" — không chụp, hiện message rồi về scanning.
  void rejectDamage() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _showContinueThenScan(confirm: false);
  }

  /// User pressed "Xác nhận" (hoặc auto sau 5 s) — chụp ảnh tổn thất, hiện
  /// message "Tiếp tục di chuyển camera…" trong 5 s rồi quay lại scanning.
  Future<void> confirmDamage({bool flashTick = true}) async {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _setInspectionPhase(InspectionPhase.capturingDamage);

    await capturePhoto(immediate: true, flashTick: flashTick);

    await _showContinueThenScan(confirm: true);
  }

  /// Hiển thị message "Tiếp tục di chuyển camera…" trong 5 s rồi quay lại
  /// scanning. Dùng chung cho cả "Xác nhận" và "Thiếu tổn thất".
  Future<void> _showContinueThenScan({required bool confirm}) async {
    _setInspectionPhase(InspectionPhase.continueOrChange);
    _setMessage(CameraMessage(
      message: confirm
          ? StringSheet.continueOrChangeGuide
          : StringSheet.moveCameraToMissing,
      type: MessageType.info,
    ));

    await Future.delayed(const Duration(seconds: 5));
    // Guard: user có thể đã bấm "Chuyển góc" trong lúc chờ.
    if (_inspectionPhase != InspectionPhase.continueOrChange) return;
    _enterScanning();
  }

  /// Called by ResultController after an angle's photos are successfully uploaded.
  /// Strips photos from memory and marks the angle completed so the progress
  /// ring stays green when the user backs out from the result screen.
  void removeUploadedPhotos(int angleId) {
    _capturedPhotos.remove(angleId);
    _completedSegments.add(angleId);
    _panoramicCapturedSegments.remove(angleId);
    notifyListeners();
  }

  /// User pressed "Chuyển góc" — thoát inspection, mở khoá classification.
  /// Giữ angle trong [_panoramicCapturedSegments] để khi quay lại sẽ vào
  /// thẳng scanning (không chụp toàn cảnh lại).
  ///
  /// Sau khi hoàn thành, hiển thị message điều hướng tới góc chưa hoàn thành
  /// tiếp theo theo thứ tự 0 → 1 → 2 → 3 (bỏ qua góc đã completed). Nếu cả 4
  /// góc đã completed thì không hiển thị message điều hướng.
  void completeCurrentAngle() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _noDetectionTimer?.cancel();
    _noDetectionTimer = null;
    final justCompleted = _activeSegmentIndex;
    if (justCompleted != null) {
      _completedSegments.add(justCompleted);
    }
    _classificationLocked = false;
    // Quay lại chọn góc → tắt carDamage (carCorner/carPart vẫn bật).
    _setInspectionPhase(null);

    final nextSegment = _nextNavigationSegment(justCompleted);
    if (nextSegment == null) {
      _setMessage(null);
    } else {
      _setMessage(CameraMessage(
        message: _segmentConfigs[nextSegment]?.$2 ?? '',
        type: MessageType.guide,
      ));
    }
  }

  /// Góc chưa completed tiếp theo theo thứ tự vòng 0 → 1 → 2 → 3, bắt đầu sau
  /// [from]. Trả về null nếu cả 4 góc đã completed.
  int? _nextNavigationSegment(int? from) {
    final start = from ?? -1;
    for (int step = 1; step <= 4; step++) {
      final idx = (start + step) % 4;
      if (!_completedSegments.contains(idx)) return idx;
    }
    return null;
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _setMessage(CameraMessage? msg) {
    if (_message == msg) return;
    _message = msg;
    notifyListeners();
  }

  /// Active của model gating đã gửi xuống native (null = chưa gửi lần nào).
  bool? _sentInspectionActive;

  /// Gán pha inspection và bật/tắt model theo pha để giảm tải:
  ///   panorama (phase == null)   → carDamage OFF, OCR ON
  ///   inspection (phase != null) → carDamage ON,  OCR OFF
  /// carCorner/carPart luôn chạy. Chỉ gửi xuống native khi trạng thái đổi.
  void _setInspectionPhase(InspectionPhase? phase) {
    _inspectionPhase = phase;
    final active = phase != null;
    if (_sentInspectionActive != active) {
      if (yoloController.setInspectionActive(active)) {
        _sentInspectionActive = active;
      }
    }
  }

  bool _stopped = false;

  /// Dừng YOLO stream và giải phóng tài nguyên native (GPU/model/camera).
  /// An toàn khi gọi nhiều lần. Gọi sớm — trước khi widget bị gỡ khỏi cây —
  /// để tránh đơ UI vì cleanup nặng chạy trong dispose().
  void stopCamera() {
    if (_stopped) return;
    _stopped = true;
    yoloController.stop();
  }

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _noDetectionTimer?.cancel();
    stopCamera(); // no-op nếu đã gọi trước đó
    super.dispose();
  }
}
