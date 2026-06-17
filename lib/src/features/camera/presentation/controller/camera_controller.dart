import 'dart:async';

import 'package:aicycle_yolo/multi_task_yolo_view.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/cache/photo_session_cache.dart';
import '../../../../core/constants/string_sheet.dart';
import '../../data/model/camera_message.dart';
import '../../data/model/car_angle.dart';
import '../../data/model/classify_output.dart';
import '../../data/model/detection_output.dart';
import '../../data/model/sementation_output.dart';

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
  Map<int, List<Uint8List>> _capturedPhotos = {};

  /// Bumped every time a photo is actually captured — the view listens to
  /// this to trigger a screen-blink (flash) effect.
  int _captureFlashTick = 0;
  CameraMessage? _message;

  /// Segment index (0–3) đang được detect, null nếu chưa nhận kết quả.
  int? _activeSegmentIndex;

  /// Angles that have a panoramic photo (inspection started but not completed).
  final Set<int> _panoramicCapturedSegments = {};

  /// When true, classify frames are ignored to lock the current angle.
  bool _classificationLocked = false;

  /// Angles fully completed (user pressed "Chuyển góc").
  final Set<int> _completedSegments = {};

  /// Class names từ frame segment mới nhất.
  Set<String> _latestSegmentClasses = {};

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
  int? get activeSegmentIndex => _activeSegmentIndex;
  Set<int> get completedSegments => Set.unmodifiable(_completedSegments);
  CameraMessage? get message => _message;
  int get captureFlashTick => _captureFlashTick;
  List<DetectionResult> get latestDetections => _latestDetections;
  InspectionPhase? get inspectionPhase => _inspectionPhase;

  /// True when actively inspecting for damage (panoramic already taken).
  bool get isInspectionMode => _inspectionPhase != null;

  /// Bounding boxes are shown only during inspection (after panoramic).
  bool get showBoundingBoxes => _inspectionPhase != null;

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

  // ── Streaming data ────────────────────────────────────────────────────────

  void onStreamingData(Map<String, dynamic> data) {
    if (data['type'] == 'classify') {
      if (_classificationLocked) return;
      final output = ClassifyOutput.fromJson(Map<String, dynamic>.from(data));
      final segment = CarAngle.segmentOf(output.classification.top1);
      if (segment == _activeSegmentIndex) return;
      _activeSegmentIndex = segment;
      // Góc này đã có ảnh toàn cảnh → bắt đầu luôn từ scanning, không cần
      // chụp toàn cảnh lại.
      if (_panoramicCapturedSegments.contains(segment)) {
        _classificationLocked = true;
        startDamageScanning();
      } else {
        updateMessage();
      }
    } else if (data['type'] == 'segment') {
      final output =
          SegmentationOutput.fromJson(Map<String, dynamic>.from(data));
      _latestSegmentClasses = output.detections.map((d) => d.className).toSet();
      updateMessage();
      return;
    } else if (data['type'] == 'detect') {
      final output = DetectionOutput.fromJson(Map<String, dynamic>.from(data));
      _latestDetections = output.detections;
      // Phát hiện tổn thất → hiển thị xác nhận ngay, không chờ timer 5s.
      _maybeShowDetectionReady();
    }
    notifyListeners();
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
  Future<Uint8List?> capturePhoto() async {
    if (_isCapturing) return null;
    _isCapturing = true;
    notifyListeners();
    try {
      /// Chụp quá nhanh, người dùng chưa kịp đọc message -> delay 3s
      await Future.delayed(const Duration(seconds: 3));
      _captureFlashTick++;

      final bytes = await yoloController.capturePhoto();
      if (_activeSegmentIndex != null) {
        _capturedPhotos.putIfAbsent(_activeSegmentIndex!, () => []).add(bytes);
        PhotoSessionCache.instance
            .savePhoto(_sessionId, _activeSegmentIndex!, bytes);
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
    _updateMessageSegment(_latestSegmentClasses, _activeSegmentIndex!);
  }

  void clearMessage() => _setMessage(null);

  void _updateMessageSegment(Set<String> classes, int segmentIndex) {
    const licencePlate = 'Biển số xe';
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
      _setMessage(CameraMessage(
          message: StringSheet.holdStillGuide, type: MessageType.loading));
      _triggerAutoCapture();
    }
  }

  Future<void> _triggerAutoCapture() async {
    await capturePhoto();
    if (_activeSegmentIndex != null) {
      _panoramicCapturedSegments.add(_activeSegmentIndex!);
      // Chụp toàn cảnh xong là góc đó đã được tính hoàn thành.
      _completedSegments.add(_activeSegmentIndex!);
    }
    _classificationLocked = true;
    _inspectionPhase = InspectionPhase.panoramicGuide;
    _setMessage(CameraMessage(
      message: StringSheet.inspectDamageGuide,
      type: MessageType.info,
    ));
  }

  // ── Inspection / damage flow ──────────────────────────────────────────────

  /// Bắt đầu (hoặc quay lại) trạng thái scanning: detection chạy theo sự kiện,
  /// đồng thời mở 10 s no-detection timeout.
  void startDamageScanning() => _enterScanning();

  void _enterScanning() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _inspectionPhase = InspectionPhase.scanning;
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
    _inspectionPhase = InspectionPhase.detectionReady;
    _setMessage(CameraMessage(
      message: StringSheet.damageDetectedGuide,
      type: MessageType.info,
    ));
    // Sau 5 s không bấm gì → tự động chụp.
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = Timer(const Duration(seconds: 5), () {
      if (_inspectionPhase == InspectionPhase.detectionReady) confirmDamage();
    });
  }

  /// 10 s ở scanning mà không phát hiện tổn thất → cảnh báo rồi rời góc.
  void _startNoDetectionTimer() {
    _noDetectionTimer?.cancel();
    _noDetectionTimer =
        Timer(const Duration(seconds: 10), _onNoDetectionTimeout);
  }

  Future<void> _onNoDetectionTimeout() async {
    if (_inspectionPhase != InspectionPhase.scanning) return;
    if (_latestDetections.isNotEmpty) return;

    _setMessage(CameraMessage(
      message: StringSheet.noDamageDetectedGuide,
      type: MessageType.warning,
    ));

    await Future.delayed(const Duration(seconds: 5));
    // Guard: angle may already have been completed/changed during the delay.
    if (_inspectionPhase != InspectionPhase.scanning) return;
    completeCurrentAngle();
  }

  /// User pressed "Thiếu tổn thất" — không chụp, hiện message rồi về scanning.
  void rejectDamage() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _showContinueThenScan();
  }

  /// User pressed "Xác nhận" (hoặc auto sau 5 s) — chụp ảnh tổn thất, hiện
  /// message "Tiếp tục di chuyển camera…" trong 5 s rồi quay lại scanning.
  Future<void> confirmDamage() async {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _inspectionPhase = InspectionPhase.capturingDamage;
    _setMessage(CameraMessage(
        message: StringSheet.holdStillGuide, type: MessageType.loading));

    await capturePhoto();

    await _showContinueThenScan();
  }

  /// Hiển thị message "Tiếp tục di chuyển camera…" trong 5 s rồi quay lại
  /// scanning. Dùng chung cho cả "Xác nhận" và "Thiếu tổn thất".
  Future<void> _showContinueThenScan() async {
    _inspectionPhase = InspectionPhase.continueOrChange;
    _setMessage(CameraMessage(
      message: StringSheet.continueOrChangeGuide,
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
    _inspectionPhase = null;
    _classificationLocked = false;

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

  @override
  void dispose() {
    _autoCaptureTimer?.cancel();
    _noDetectionTimer?.cancel();
    yoloController.stop();
    super.dispose();
  }
}
