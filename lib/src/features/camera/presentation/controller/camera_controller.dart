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

  /// Waiting 5 s for detections. No tooltip shown.
  scanning,

  /// Detections found after 5 s — showing "Xác nhận / Thiếu tổn thất".
  detectionReady,

  /// User tapped "Xác nhận" — capturing damage photo + loading spinner.
  capturingDamage,

  /// Damage captured — showing success toast for 3 s.
  captureSuccessful,

  /// After success: "Tiếp tục… hoặc Chuyển góc" + 5 s cycle resumes.
  continueOrChange,
}

class CameraController extends ChangeNotifier {
  CameraController({required String sessionId}) : _sessionId = sessionId;

  final String _sessionId;
  final yoloController = MultiTaskYOLOController();

  bool _torchEnabled = false;
  bool _isCapturing = false;
  Map<int, List<Uint8List>> _capturedPhotos = {};
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

  /// 5-second damage detection timer.
  Timer? _damageTimer;

  // ── Getters ──────────────────────────────────────────────────────────────

  bool get isTorchEnabled => _torchEnabled;
  bool get isCapturing => _isCapturing;
  Map<int, List<Uint8List>> get capturedPhotos => _capturedPhotos;
  int? get activeSegmentIndex => _activeSegmentIndex;
  Set<int> get completedSegments => Set.unmodifiable(_completedSegments);
  CameraMessage? get message => _message;
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
      updateMessage();
    } else if (data['type'] == 'segment') {
      final output =
          SegmentationOutput.fromJson(Map<String, dynamic>.from(data));
      _latestSegmentClasses =
          output.detections.map((d) => d.className).toSet();
      updateMessage();
      return;
    } else if (data['type'] == 'detect') {
      final output = DetectionOutput.fromJson(Map<String, dynamic>.from(data));
      _latestDetections = output.detections;
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
      final bytes = await yoloController.capturePhoto();
      if (_activeSegmentIndex != null) {
        _capturedPhotos
            .putIfAbsent(_activeSegmentIndex!, () => [])
            .add(bytes);
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
    }
    _classificationLocked = true;
    _inspectionPhase = InspectionPhase.panoramicGuide;
    _setMessage(CameraMessage(
      message: StringSheet.inspectDamageGuide,
      type: MessageType.info,
    ));
  }

  // ── Inspection / damage flow ──────────────────────────────────────────────

  /// User pressed X on panoramicGuide → start 5 s damage scanning loop.
  void startDamageScanning() {
    _inspectionPhase = InspectionPhase.scanning;
    _setMessage(null);
    _startDamageTimer();
  }

  void _startDamageTimer() {
    _damageTimer?.cancel();
    _damageTimer =
        Timer(const Duration(seconds: 5), _onDamageTimerFired);
  }

  void _onDamageTimerFired() {
    if (_inspectionPhase != InspectionPhase.scanning &&
        _inspectionPhase != InspectionPhase.continueOrChange) {
      return;
    }

    if (_latestDetections.isNotEmpty) {
      _inspectionPhase = InspectionPhase.detectionReady;
      _setMessage(CameraMessage(
        message: StringSheet.damageDetectedGuide,
        type: MessageType.info,
      ));
    } else {
      // No detections yet — keep scanning
      _startDamageTimer();
    }
  }

  /// User pressed "Thiếu tổn thất" — reset the 5 s timer.
  void rejectDamage() {
    _inspectionPhase = InspectionPhase.scanning;
    _setMessage(null);
    _startDamageTimer();
  }

  /// User pressed "Xác nhận" — capture damage photo, show success, then loop.
  Future<void> confirmDamage() async {
    _damageTimer?.cancel();
    _inspectionPhase = InspectionPhase.capturingDamage;
    _setMessage(CameraMessage(
        message: StringSheet.holdStillGuide, type: MessageType.loading));

    await capturePhoto();

    _inspectionPhase = InspectionPhase.captureSuccessful;
    _setMessage(CameraMessage(
        message: StringSheet.captureSuccess, type: MessageType.success));

    await Future.delayed(const Duration(seconds: 3));
    // Guard: if the angle was completed during the delay, don't override.
    if (_inspectionPhase != InspectionPhase.captureSuccessful) return;

    _inspectionPhase = InspectionPhase.continueOrChange;
    _setMessage(CameraMessage(
      message: StringSheet.continueOrChangeGuide,
      type: MessageType.info,
    ));
    // Resume 5 s cycle from the "continue or change" state.
    _startDamageTimer();
  }

  /// User pressed "Chuyển góc" (from panoramicGuide or continueOrChange).
  void completeCurrentAngle() {
    _damageTimer?.cancel();
    _damageTimer = null;
    if (_activeSegmentIndex == null) return;
    _completedSegments.add(_activeSegmentIndex!);
    _panoramicCapturedSegments.remove(_activeSegmentIndex!);
    _inspectionPhase = null;
    _classificationLocked = false;
    _setMessage(null);
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _setMessage(CameraMessage? msg) {
    if (_message == msg) return;
    _message = msg;
    notifyListeners();
  }

  @override
  void dispose() {
    _damageTimer?.cancel();
    yoloController.stop();
    super.dispose();
  }
}
