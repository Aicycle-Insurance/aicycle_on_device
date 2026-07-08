import 'dart:async';

import '../../../../yolo/multi_task_yolo_view.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/cache/photo_session_cache.dart';
import '../../../../core/constants/string_sheet.dart';
import '../../data/model/camera_message.dart';
import '../../data/model/car_angle.dart';
import '../../data/model/classify_output.dart';
import '../../data/model/detection_output.dart';

part 'camera_controller.stream.dart';
part 'camera_controller.capture.dart';
part 'camera_controller.panoramic.dart';
part 'camera_controller.inspection.dart';

/// Sub-states of the damage inspection flow (active when panoramic photo is taken).
enum InspectionPhase {
  /// Initial message: "Đưa camera lại gần tổn thất…". Damage detections can
  /// move straight to confirmation; detecting a different car angle completes
  /// the current angle automatically.
  panoramicGuide,

  /// Scanning for damage. Detection is event-driven: ngay khi có detection
  /// → detectionReady. Sau 10 s không có detection → warning.
  scanning,

  /// Detections found — showing "Xác nhận / Thiếu tổn thất". Sau 10 s không
  /// bấm gì sẽ tự động chụp ngầm lặp lại, nhưng vẫn giữ tooltip cho tới khi
  /// user bấm "Xác nhận" hoặc "Thiếu tổn thất". Dùng cho cả ảnh tổng quan
  /// (overview) lẫn ảnh chi tiết (detail) — phân biệt bằng
  /// [_CameraControllerBase._inDetailStage].
  detectionReady,

  /// Đang chụp ảnh tổn thất (tự động hoặc do bấm "Xác nhận").
  capturingDamage,

  /// Sau khi chụp ảnh tổng quan: nhắc "Di chuyển camera đến gần vùng có tổn
  /// thất để chụp ảnh chi tiết". Nếu sau 10 s vẫn chưa nhận diện tổn thất thì
  /// tự chụp một ảnh; sau thêm 5 s vẫn chưa nhận diện thì chuyển sang nhắc di
  /// chuyển tới vùng tổn thất khác.
  detailGuide,

  /// Hiển thị message "Tiếp tục di chuyển camera…" trong 5 s rồi quay lại
  /// scanning.
  continueOrChange,
}

/// Tên class biển số xe trong model car-part (khớp với logic native OCR).
const _licensePlateClass = 'Biển số xe';

/// Giữ message holdStill tối thiểu khoảng này, tránh OCR đọc nhanh khiến message
/// flash qua quá nhanh user không kịp thấy.
const _holdStillMinDuration = Duration(seconds: 3);

/// OCR đọc được biển số chỉ có hiệu lực rất ngắn. Nếu user lia máy làm biển
/// lệch/lẹm sau frame OCR đó thì controller phải chờ OCR đọc lại ở frame mới,
/// không dùng trạng thái cũ để auto-capture.
const _plateReadFreshDuration = Duration(milliseconds: 700);

/// Giữ message yêu cầu căn biển rõ tối thiểu khoảng này trước khi cho phép
/// auto-capture lại, để user kịp đọc và điều chỉnh camera.
const _plateClearPromptMinDuration = Duration(seconds: 3);

/// Giữ thông báo chụp thành công đủ lâu để user kịp đọc trước khi chuyển sang
/// hướng dẫn tiếp theo.
const _captureSuccessVisibleDuration = Duration(seconds: 3);

/// Mỗi tooltip khi đã xuất hiện phải được giữ tối thiểu khoảng này trước khi
/// một message/phase khác thay thế, để tránh user chưa kịp đọc.
const _tooltipMinVisibleDuration = Duration(seconds: 3);

/// Nhịp chụp tự động khi đang ở màn xác nhận tổn thất.
const _damageAutoCaptureInterval = Duration(seconds: 10);

/// Ở pha chụp ảnh chi tiết, chờ user đưa camera lại gần trước khi auto-capture.
const _detailAutoCaptureDelay = Duration(seconds: 10);

/// Sau ảnh chi tiết tự động, nếu vẫn không nhận diện thì chuyển hướng user.
const _detailPostCaptureNoDetectionDelay = Duration(seconds: 5);

/// Cấu hình mỗi góc: (tên ba đờ sốc cần thấy, message điều hướng tới góc đó).
const _segmentConfigs = {
  0: ('Ba đờ sốc trước', StringSheet.frontRightGuide),
  1: ('Ba đờ sốc sau', StringSheet.backRightGuide),
  2: ('Ba đờ sốc sau', StringSheet.backLeftGuide),
  3: ('Ba đờ sốc trước', StringSheet.frontLeftGuide),
};

/// Controller điều phối luồng chụp ảnh + soi tổn thất. Hành vi được chia thành
/// các mixin (trên cùng [_CameraControllerBase], state dùng chung):
///   * [_StreamMixin]     — phân loại frame YOLO (classify / ocr / carPart / carDamage).
///   * [_CaptureMixin]    — chụp & lưu ảnh, khôi phục cache.
///   * [_PanoramicMixin]  — canh khung + OCR biển số cho ảnh toàn cảnh.
///   * [_InspectionMixin] — máy trạng thái soi tổn thất (scanning → detail → …).
// ignore: library_private_types_in_public_api
class CameraController = _CameraControllerBase
    with _StreamMixin, _CaptureMixin, _PanoramicMixin, _InspectionMixin;

/// State dùng chung cho mọi mixin + các helper cốt lõi (message, viewport, phase,
/// lifecycle). Các entry-point gọi chéo giữa mixin được khai báo abstract ở đây.
abstract class _CameraControllerBase extends ChangeNotifier {
  _CameraControllerBase({
    required String sessionId,
    bool require4Angles = false,
  })  : _sessionId = sessionId,
        _require4Angles = require4Angles;

  final String _sessionId;

  /// Config "Require 4-angle panoramic photos". Khi TẮT (false): chỉ ảnh đầu
  /// tiên cần là ảnh toàn cảnh đọc rõ biển số; các góc sau chỉ ghi nhận tổn
  /// thất (vào thẳng scanning, không yêu cầu chụp toàn cảnh, không nhắc "di
  /// chuyển về góc chéo"). Vòng tròn góc: góc nào đã có ảnh thì hiện màu xanh.
  final bool _require4Angles;

  final yoloController = MultiTaskYOLOController();

  bool _torchEnabled = false;
  bool _isCapturing = false;

  /// User chưa bấm "Bắt đầu chụp ảnh xe" (guide sheet) → tạm bỏ qua mọi output
  /// streaming từ YOLO. Bật lên qua [_StreamMixin.startCapture].
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
  InspectionPhase? _messagePhase;
  DateTime? _messageShownAt;
  CameraMessage? _pendingMessage;
  InspectionPhase? _pendingMessagePhase;
  Timer? _pendingMessageTimer;

  /// Segment index (0–3) đang được detect, null nếu chưa nhận kết quả.
  /// Đây là góc cho LUỒNG xử lý (bị khoá khi [_classificationLocked]).
  int? _activeSegmentIndex;

  /// Góc (0–3) đang được classify nhận diện trực tiếp ở frame mới nhất — luôn
  /// cập nhật bất kể flow có khoá hay không, dùng để highlight trên UI.
  int? _detectedSegmentIndex;

  /// Angles that have a panoramic photo (inspection started but not completed).
  final Set<int> _panoramicCapturedSegments = {};

  /// Latch: đã chụp xong ảnh toàn cảnh ĐẦU TIÊN (đọc rõ biển số) chưa. Khi
  /// [_require4Angles] = false, sau mốc này các góc khác bỏ qua bước chụp toàn
  /// cảnh và vào thẳng scanning.
  bool _firstPanoramicCaptured = false;

  /// When true, classify frames are ignored to lock the current angle.
  bool _classificationLocked = false;

  /// Angles fully completed (auto-switched to another detected car angle).
  final Set<int> _completedSegments = {};

  /// Class names bộ phận từ frame car-part detect (model thứ 2) mới nhất.
  Set<String> _latestCarPartClasses = {};

  /// OCR (native) đọc được biển số ở frame mới nhất hay chưa. Là tín hiệu canh
  /// khung: đọc được biển ⇒ khung đủ rõ/đủ gần để dùng làm ảnh toàn cảnh.
  bool _latestPlateReadable = false;

  /// Thời điểm frame OCR mới nhất đọc được biển. Dùng để loại tín hiệu OCR cũ
  /// khi camera đã dịch khỏi vị trí vừa đọc biển.
  DateTime? _latestPlateReadableAt;

  /// Timer 5s: khi đã căn đủ bộ phận nhưng OCR chưa đọc được biển hợp lệ, hết
  /// 5s thì nhắc user di chuyển cho biển rõ nét.
  Timer? _plateReadTimer;

  /// Đã hiển thị nhắc "di chuyển cho biển rõ" hay chưa — để frame carPart kế
  /// tiếp không ghi đè message về holdStill.
  bool _platePromptShown = false;

  /// Mốc bắt đầu hiển thị nhắc "di chuyển cho biển rõ". Dùng để giữ warning tối
  /// thiểu 3s trước khi auto-capture lại nếu OCR đọc được biển ngay sau đó.
  DateTime? _platePromptShownAt;

  /// Mốc thời điểm bắt đầu hiển thị "giữ yên" (đã căn đủ bộ phận). Dùng để giữ
  /// message holdStill tối thiểu 3s, tránh OCR đọc nhanh khiến message flash qua
  /// quá nhanh user không kịp thấy.
  DateTime? _holdStillShownAt;

  /// Chi tiết bộ phận (kèm bounding box) từ frame car-part detect mới nhất —
  /// dùng để vẽ nhãn tên bộ phận lên màn hình.
  List<DetectionResult> _latestCarPartDetections = [];

  /// Detections từ frame detect mới nhất.
  List<DetectionResult> _latestDetections = [];

  /// Current phase of the damage inspection sub-flow. null = not in inspection.
  InspectionPhase? _inspectionPhase;

  /// Timer chạy ở detectionReady: cứ mỗi 10s tự động chụp ngầm một ảnh tổn
  /// thất cho tới khi user bấm "Xác nhận" hoặc "Thiếu tổn thất".
  Timer? _autoCaptureTimer;

  /// One-shot timer: nếu sau 10 s vẫn chưa phát hiện tổn thất ở pha chờ/quét
  /// thì hiển thị warning, nhưng không tự rời góc.
  Timer? _noDetectionWarningTimer;

  /// Timer của pha [InspectionPhase.detailGuide] (chụp ảnh chi tiết).
  Timer? _detailTimer;

  /// True khi detectionReady đến từ pha detailGuide (đang chờ xác nhận ảnh chi
  /// tiết) — phân biệt với ảnh tổng quan để biết bước kế tiếp sau khi chụp.
  bool _inDetailStage = false;

  /// Active của model gating đã gửi xuống native (null = chưa gửi lần nào).
  bool? _sentInspectionActive;

  bool _stopped = false;

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isTorchEnabled => _torchEnabled;
  bool get isCapturing => _isCapturing;
  Map<int, List<Uint8List>> get capturedPhotos => _capturedPhotos;
  int? get activeSegmentIndex => _detectedSegmentIndex ?? _activeSegmentIndex;
  Set<int> get completedSegments => Set.unmodifiable(_completedSegments);

  /// Khi config 4 góc TẮT: trên vòng tròn góc, góc đã có ảnh (đã hoàn thành)
  /// hiện màu xanh đè lên highlight vàng — kể cả khi camera đang chĩa vào góc
  /// đó. (Flow 4 góc giữ nguyên: highlight vàng đè lên xanh.)
  bool get completedTakesPriority => !_require4Angles;
  CameraMessage? get message => _message;
  InspectionPhase? get messagePhase => _messagePhase;
  int get captureFlashTick => _captureFlashTick;
  List<DetectionResult> get latestDetections => _latestDetections;
  List<DetectionResult> get latestCarPartDetections => _latestCarPartDetections;
  InspectionPhase? get inspectionPhase => _inspectionPhase;

  /// True when actively inspecting for damage (panoramic already taken).
  bool get isInspectionMode => _inspectionPhase != null;

  /// Bounding boxes are shown only during inspection (after panoramic).
  bool get showBoundingBoxes => _inspectionPhase != null;

  // ── Viewport ───────────────────────────────────────────────────────────────

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

  bool get _hasFreshPlateRead {
    final readAt = _latestPlateReadableAt;
    if (!_latestPlateReadable || readAt == null) return false;
    if (DateTime.now().difference(readAt) <= _plateReadFreshDuration) {
      return true;
    }
    _clearPlateRead();
    return false;
  }

  void _clearPlateRead() {
    _latestPlateReadable = false;
    _latestPlateReadableAt = null;
  }

  void _resetPanoramicFramingState({bool clearCarParts = false}) {
    _clearPlateRead();
    _holdStillShownAt = null;
    _plateReadTimer?.cancel();
    _plateReadTimer = null;
    _platePromptShown = false;
    _platePromptShownAt = null;
    if (clearCarParts) {
      _latestCarPartClasses = {};
      _latestCarPartDetections = [];
    }
  }

  // ── Torch ─────────────────────────────────────────────────────────────────

  Future<void> toggleFlash() async {
    final actual = await yoloController.setTorch(!_torchEnabled);
    _torchEnabled = actual;
    notifyListeners();
  }

  // ── Message / phase helpers ────────────────────────────────────────────────

  void clearMessage() => _setMessage(null);

  void _setMessage(CameraMessage? msg, {bool immediate = false}) {
    final phase = _inspectionPhase;
    if (immediate) {
      _applyMessage(msg, phase);
      return;
    }

    if (_isSameMessageState(_message, _messagePhase, msg, phase)) {
      _cancelPendingMessage();
      return;
    }
    if (_isSameMessageState(
        _pendingMessage, _pendingMessagePhase, msg, phase)) {
      return;
    }

    final remaining = _tooltipRemainingVisibleDuration;
    if (remaining > Duration.zero) {
      _cancelPendingMessage();
      _pendingMessage = msg;
      _pendingMessagePhase = phase;
      _pendingMessageTimer = Timer(remaining, () {
        final pendingMessage = _pendingMessage;
        final pendingPhase = _pendingMessagePhase;
        _pendingMessage = null;
        _pendingMessagePhase = null;
        _pendingMessageTimer = null;
        _applyMessage(pendingMessage, pendingPhase);
      });
      return;
    }

    _applyMessage(msg, phase);
  }

  bool _isSameMessageState(
    CameraMessage? a,
    InspectionPhase? aPhase,
    CameraMessage? b,
    InspectionPhase? bPhase,
  ) {
    if (a == null || b == null) return a == null && b == null;
    return a.message == b.message && a.type == b.type && aPhase == bPhase;
  }

  Duration get _tooltipRemainingVisibleDuration {
    final shownAt = _messageShownAt;
    if (_message == null || shownAt == null) return Duration.zero;
    final visibleDuration = DateTime.now().difference(shownAt);
    if (visibleDuration >= _tooltipMinVisibleDuration) return Duration.zero;
    return _tooltipMinVisibleDuration - visibleDuration;
  }

  void _cancelPendingMessage() {
    _pendingMessageTimer?.cancel();
    _pendingMessageTimer = null;
    _pendingMessage = null;
    _pendingMessagePhase = null;
  }

  void _applyMessage(CameraMessage? msg, InspectionPhase? phase) {
    _cancelPendingMessage();
    if (_isSameMessageState(_message, _messagePhase, msg, phase)) return;
    _message = msg;
    _messagePhase = msg == null ? null : phase;
    _messageShownAt = msg == null ? null : DateTime.now();
    notifyListeners();
  }

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

  // ── Lifecycle ───────────────────────────────────────────────────────────────

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
    _noDetectionWarningTimer?.cancel();
    _detailTimer?.cancel();
    _plateReadTimer?.cancel();
    _cancelPendingMessage();
    stopCamera(); // no-op nếu đã gọi trước đó
    super.dispose();
  }

  // ── Cross-mixin entry points (implemented in mixins) ───────────────────────

  /// [_PanoramicMixin] — cập nhật message canh khung theo bộ phận/OCR.
  Future<void> updateMessage();

  /// [_InspectionMixin] — bắt đầu (hoặc quay lại) trạng thái scanning.
  void startDamageScanning();

  /// [_InspectionMixin] — phát hiện tổn thất → mở xác nhận.
  void _maybeShowDetectionReady();

  /// [_InspectionMixin] — mở 10 s no-detection warning timeout.
  void _startNoDetectionWarningTimer();

  /// [_InspectionMixin] — sau khi user chụp manual từ warning không nhận diện
  /// tổn thất, hiển thị hướng dẫn di chuyển tiếp rồi quay lại scanning.
  Future<void> _showManualCaptureContinueGuide();

  /// [_InspectionMixin] — tự động rời góc hiện tại khi classifier nhận diện
  /// user đã di chuyển sang góc xe khác.
  void _autoSwitchToDetectedSegment(int segment);

  /// [_CaptureMixin] — chụp 1 ảnh JPEG, lưu in-memory + disk.
  Future<Uint8List?> capturePhoto({
    bool immediate = false,
    int? segment,
    bool flashTick = true,
  });
}
