import 'dart:async';

import '../../../../yolo/multi_task_yolo_view.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/cache/photo_session_cache.dart';
import '../../../../core/constants/string_sheet.dart';
import '../../../../core/upload/photo_upload_queue.dart';
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
  /// bấm gì sẽ tự động xác nhận: chụp + hiển thị thông báo như bấm "Xác nhận"
  /// (không blink). Dùng cho cả ảnh tổng quan (overview) lẫn ảnh chi tiết
  /// (detail) — phân biệt bằng [_CameraControllerBase._inDetailStage].
  detectionReady,

  /// Đang chụp ảnh tổn thất (tự động hoặc do bấm "Xác nhận").
  capturingDamage,

  /// Sau khi chụp ảnh tổng quan: nhắc "Di chuyển camera đến gần vùng có tổn
  /// thất để chụp ảnh chi tiết". Nếu sau 10 s vẫn chưa nhận diện tổn thất thì
  /// tự chụp một ảnh; sau thêm 5 s vẫn chưa nhận diện thì chuyển sang nhắc di
  /// chuyển tới vùng tổn thất khác.
  detailGuide,

  /// Hiển thị message "Tiếp tục di chuyển camera…" trong 10 s rồi quay lại
  /// scanning.
  continueOrChange,
}

/// Tên class biển số xe trong model car-part (khớp với logic native OCR).
const _licensePlateClass = 'Biển số xe';

/// Giữ message holdStill tối thiểu khoảng này, tránh OCR đọc nhanh khiến message
/// flash qua quá nhanh user không kịp thấy.
const _holdStillMinDuration = Duration(milliseconds: 800);

/// OCR đọc được biển số chỉ có hiệu lực rất ngắn. Nếu user lia máy làm biển
/// lệch/lẹm sau frame OCR đó thì controller phải chờ OCR đọc lại ở frame mới,
/// không dùng trạng thái cũ để auto-capture.
const _plateReadFreshDuration = Duration(milliseconds: 1200);

/// Model carPart (~6.7fps) nhấp nháy giữa các frame: một bộ phận vẫn được coi
/// là "đang thấy" nếu xuất hiện trong khoảng này (~4 frame), để một frame nhiễu
/// không reset đồng hồ giữ yên 3s / xoá cờ đọc biển. User thực sự lia máy đi
/// thì bộ phận biến mất quá khoảng này và trạng thái reset như cũ.
const _carPartFlickerGrace = Duration(milliseconds: 600);

/// Giữ message yêu cầu căn biển rõ tối thiểu khoảng này trước khi cho phép
/// auto-capture lại, để user kịp đọc và điều chỉnh camera.
const _plateClearPromptMinDuration = Duration(seconds: 1);

/// Khi đã căn đủ thân xe nhưng OCR chưa đọc được biển, nhắc điều chỉnh sớm
/// thay vì để user giữ máy chờ mà không biết nguyên nhân.
const _plateReadPromptDelay = Duration(seconds: 2);

/// Giữ thông báo chụp thành công đủ lâu để user kịp đọc trước khi chuyển sang
/// hướng dẫn tiếp theo.
const _captureSuccessVisibleDuration = Duration(seconds: 1);

/// Mỗi tooltip khi đã xuất hiện phải được giữ tối thiểu khoảng này trước khi
/// một message/phase khác thay thế, để tránh user chưa kịp đọc.
const _tooltipMinVisibleDuration = Duration(seconds: 3);

/// Sau khi chụp, ảnh vừa chụp được vẽ đè lên preview và "dừng hình" khoảng này —
/// chụp (nhất là auto-capture ảnh toàn cảnh) diễn ra rất nhanh, chỉ một nháy
/// trắng thì user không kịp nhận ra đã có ảnh.
const _captureFreezeHoldDuration = Duration(milliseconds: 700);

/// Hết nhịp dừng hình, ảnh co nhỏ dần về thumbnail góc dưới trái trong khoảng
/// này để user thấy rõ ảnh "đi vào" thư viện.
const _captureFreezeShrinkDuration = Duration(milliseconds: 450);

/// Ở màn xác nhận tổn thất: sau khoảng này không bấm gì → tự động xác nhận
/// (chụp + hiển thị thông báo như bấm "Xác nhận", không blink).
const _damageAutoCaptureInterval = Duration(seconds: 5);

/// Ở pha chụp ảnh chi tiết, chờ user đưa camera lại gần trước khi auto-capture.
const _detailAutoCaptureDelay = Duration(seconds: 5);

/// Giữ hướng dẫn "Di chuyển camera đến gần tổn thất…" (detailGuide) tối thiểu
/// khoảng này trước khi cho phép detection mở lại màn xác nhận — để user kịp
/// đọc, tránh bị bounce liên tiếp giữa 2 tooltip khi AI nhận diện liên tục.
const _detailGuideMinVisibleDuration = Duration(seconds: 5);

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

  Map<int, List<String>> _capturedPhotos = {};

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

  /// Ảnh của lượt "dừng hình + co về thumbnail" gần nhất, và tick để view biết
  /// có lượt mới cần chạy hiệu ứng.
  String? _captureFreezePath;
  int _captureFreezeTick = 0;

  /// True trong ~0.5s sau MỖI lần chụp (kể cả chụp ngầm không blink) —
  /// CameraFrameCorners hiển thị trạng thái success trong khoảng này.
  bool _cornerSuccessActive = false;
  Timer? _cornerSuccessTimer;
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

  /// Thời điểm thấy gần nhất của từng bộ phận (trong khung nhìn). Dùng cùng
  /// [_carPartFlickerGrace] để làm mượt tín hiệu detect vốn nhấp nháy từng frame.
  final Map<String, DateTime> _carPartLastSeenAt = {};

  /// OCR (native) đọc được biển số ở frame mới nhất hay chưa. Là tín hiệu canh
  /// khung: đọc được biển ⇒ khung đủ rõ/đủ gần để dùng làm ảnh toàn cảnh.
  bool _latestPlateReadable = false;

  /// Thời điểm frame OCR mới nhất đọc được biển. Dùng để loại tín hiệu OCR cũ
  /// khi camera đã dịch khỏi vị trí vừa đọc biển.
  DateTime? _latestPlateReadableAt;

  /// Timer ngắn: khi đã căn đủ bộ phận nhưng OCR chưa đọc được biển hợp lệ thì
  /// nhắc user di chuyển cho biển rõ nét.
  Timer? _plateReadTimer;

  /// Đã hiển thị nhắc "di chuyển cho biển rõ" hay chưa — để frame carPart kế
  /// tiếp không ghi đè message về holdStill.
  bool _platePromptShown = false;

  /// Mốc bắt đầu hiển thị nhắc "di chuyển cho biển rõ". Dùng để giữ warning đủ
  /// lâu trước khi auto-capture lại nếu OCR đọc được biển ngay sau đó.
  DateTime? _platePromptShownAt;

  /// Mốc thời điểm bắt đầu hiển thị "giữ yên" (đã căn đủ bộ phận). Dùng để giữ
  /// message holdStill trong một nhịp ngắn, vừa ổn định khung vừa tránh làm chậm
  /// lần chụp khi OCR đã đọc tốt.
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

  /// Mốc bắt đầu hiển thị hướng dẫn detailGuide ("Di chuyển camera đến gần
  /// tổn thất…"). Detection chỉ được mở lại màn xác nhận sau khi hướng dẫn đã
  /// hiển thị tối thiểu [_detailGuideMinVisibleDuration].
  DateTime? _detailGuideShownAt;

  /// True khi detectionReady đến từ pha detailGuide (đang chờ xác nhận ảnh chi
  /// tiết) — phân biệt với ảnh tổng quan để biết bước kế tiếp sau khi chụp.
  bool _inDetailStage = false;

  /// Active của model gating đã gửi xuống native (null = chưa gửi lần nào).
  bool? _sentInspectionActive;

  bool _stopped = false;

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isTorchEnabled => _torchEnabled;
  bool get isCapturing => _isCapturing;
  Map<int, List<String>> get capturedPhotos => _capturedPhotos;
  int? get activeSegmentIndex => _detectedSegmentIndex ?? _activeSegmentIndex;
  Set<int> get completedSegments => Set.unmodifiable(_completedSegments);

  /// Khi config 4 góc TẮT: trên vòng tròn góc, góc đã có ảnh (đã hoàn thành)
  /// hiện màu xanh đè lên highlight vàng — kể cả khi camera đang chĩa vào góc
  /// đó. (Flow 4 góc giữ nguyên: highlight vàng đè lên xanh.)
  bool get completedTakesPriority => !_require4Angles;
  CameraMessage? get message => _message;
  InspectionPhase? get messagePhase => _messagePhase;
  int get captureFlashTick => _captureFlashTick;
  bool get cornerSuccessActive => _cornerSuccessActive;

  /// Hiệu ứng "dừng hình rồi co ảnh về thumbnail" — view đọc path/tick để chạy
  /// animation, và dùng 2 duration để chia 2 pha đúng bằng thời gian controller
  /// đang chờ.
  String? get captureFreezePath => _captureFreezePath;
  int get captureFreezeTick => _captureFreezeTick;
  Duration get captureFreezeHoldDuration => _captureFreezeHoldDuration;
  Duration get captureFreezeShrinkDuration => _captureFreezeShrinkDuration;
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

  /// Bộ phận [className] có được thấy trong khoảng [_carPartFlickerGrace] gần
  /// đây không — tín hiệu "đang thấy" đã làm mượt qua các frame nhiễu.
  bool _seenRecently(String className) {
    final seenAt = _carPartLastSeenAt[className];
    return seenAt != null &&
        DateTime.now().difference(seenAt) <= _carPartFlickerGrace;
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
      _carPartLastSeenAt.clear();
    }
  }

  // ── Corner success flash ──────────────────────────────────────────────────

  /// Nháy trạng thái success trên CameraFrameCorners trong [duration]. Gọi ở
  /// đúng khoảnh khắc chụp để đồng bộ với blink (nếu có); truyền duration dài
  /// hơn để giữ viền theo thời gian hiển thị message (vd bấm "Xác nhận").
  void _flashCornerSuccess(Duration duration) {
    _cornerSuccessActive = true;
    _cornerSuccessTimer?.cancel();
    _cornerSuccessTimer = Timer(duration, () {
      _cornerSuccessTimer = null;
      _cornerSuccessActive = false;
      notifyListeners();
    });
    notifyListeners();
  }

  // ── Capture freeze ────────────────────────────────────────────────────────

  /// Dừng hình ảnh vừa chụp trên preview rồi co nhỏ về thumbnail, và CHỜ hết
  /// hiệu ứng. Chờ ngay trong luồng chụp để message/pha kế tiếp không cắt ngang
  /// animation — đây cũng chính là nhịp delay giúp user kịp thấy ảnh đã chụp.
  Future<void> _playCaptureFreeze(String photoPath) async {
    if (_stopped) return;
    _captureFreezePath = photoPath;
    _captureFreezeTick++;
    notifyListeners();
    await Future.delayed(_captureFreezeDuration);
  }

  /// Tổng thời gian dừng hình + co ảnh về thumbnail.
  Duration get _captureFreezeDuration =>
      _captureFreezeHoldDuration + _captureFreezeShrinkDuration;

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
    _captureStarted = false;
    _cancelFlowTimers();
    _latestDetections = [];
    _latestCarPartDetections = [];
    _latestCarPartClasses = {};
    _torchEnabled = false;
    unawaited(yoloController.stop().catchError((_) {}));
  }

  void _cancelFlowTimers() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _noDetectionWarningTimer?.cancel();
    _noDetectionWarningTimer = null;
    _detailTimer?.cancel();
    _detailTimer = null;
    _plateReadTimer?.cancel();
    _plateReadTimer = null;
    _cornerSuccessTimer?.cancel();
    _cornerSuccessTimer = null;
    _cancelPendingMessage();
  }

  @override
  void dispose() {
    _cancelFlowTimers();
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

  /// [_CaptureMixin] — chụp 1 ảnh JPEG xuống disk và enqueue upload nền.
  Future<String?> capturePhoto({
    bool immediate = false,
    int? segment,
    bool flashTick = true,
  });
}
