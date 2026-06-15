import 'package:aicycle_yolo/multi_task_yolo_view.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/cache/photo_session_cache.dart';
import '../../../../core/constants/string_sheet.dart';
import '../../data/model/camera_message.dart';
import '../../data/model/car_angle.dart';
import '../../data/model/classify_output.dart';
import '../../data/model/detection_output.dart';
import '../../data/model/sementation_output.dart';

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

  /// Các segment đã chụp ảnh toàn cảnh và đang ở chế độ kiểm tra tổn thất.
  final Set<int> _panoramicCapturedSegments = {};

  /// Khi true, kết quả classify bị bỏ qua để giữ nguyên góc hiện tại.
  bool _classificationLocked = false;

  /// Các segment đã hoàn thành (user ấn "Chuyển góc").
  final Set<int> _completedSegments = {};

  /// Class names từ frame segment mới nhất.
  Set<String> _latestSegmentClasses = {};

  /// Detections từ frame detect mới nhất.
  List<DetectionResult> _latestDetections = [];

  bool get isTorchEnabled => _torchEnabled;
  bool get isCapturing => _isCapturing;
  Map<int, List<Uint8List>> get capturedPhotos => _capturedPhotos;
  int? get activeSegmentIndex => _activeSegmentIndex;
  Set<int> get completedSegments => Set.unmodifiable(_completedSegments);
  CameraMessage? get message => _message;
  List<DetectionResult> get latestDetections => _latestDetections;

  /// True khi ảnh toàn cảnh đã chụp và đang ở chế độ kiểm tra tổn thất.
  bool get isInspectionMode =>
      _activeSegmentIndex != null &&
      _panoramicCapturedSegments.contains(_activeSegmentIndex);

  /// Restores previously captured photos from disk cache.
  /// Call once after construction; notifies listeners when done.
  Future<void> loadCachedPhotos() async {
    final cached = await PhotoSessionCache.instance.loadSession(_sessionId);
    if (cached.isEmpty) return;
    _capturedPhotos = cached;
    _completedSegments.addAll(cached.keys);
    notifyListeners();
  }

  /// Processes streaming data from the YOLO model.
  ///
  /// Handles different data types:
  /// - 'classify': Updates the active segment based on classification results
  /// - 'segment': Processes segmentation detections and updates UI messages
  /// - 'detect': Detection results (currently not implemented)
  ///
  /// Gọi từ [MultiTaskYOLOView.onStreamingData].
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
      _latestSegmentClasses = output.detections.map((d) => d.className).toSet();
      updateMessage();
      return;
    } else if (data['type'] == 'detect') {
      final output = DetectionOutput.fromJson(Map<String, dynamic>.from(data));
      _latestDetections = output.detections;
    }
    notifyListeners();
  }

  /// Toggles the flashlight/torch on or off.
  ///
  /// Requests the YOLO controller to toggle the torch and updates the internal state
  /// with the actual result, then notifies listeners of the change.
  Future<void> toggleFlash() async {
    final actual = await yoloController.setTorch(!_torchEnabled);
    _torchEnabled = actual;
    notifyListeners();
  }

  /// Captures a photo from the camera and stores it.
  ///
  /// Returns null if already capturing. Captures the photo, stores it in [_capturedPhotos]
  /// keyed by the current segment index, and marks the segment as completed.
  /// Notifies listeners after completion.
  Future<Uint8List?> capturePhoto() async {
    if (_isCapturing) return null;
    _isCapturing = true;
    notifyListeners();
    try {
      final bytes = await yoloController.capturePhoto();
      if (_activeSegmentIndex != null) {
        _capturedPhotos.putIfAbsent(_activeSegmentIndex!, () => []).add(bytes);
        _completedSegments.add(_activeSegmentIndex!);
        // Persist to disk so photos survive app kill
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

  /// Segment configuration: [bumper type, initial guide message]
  static const _segmentConfigs = {
    0: ('Ba đờ sốc trước', StringSheet.frontRightGuide),
    1: ('Ba đờ sốc sau', StringSheet.backRightGuide),
    2: ('Ba đờ sốc sau', StringSheet.backLeftGuide),
    3: ('Ba đờ sốc trước', StringSheet.frontLeftGuide),
  };

  /// Updates the UI guidance message based on the current segment and detected classes.
  ///
  /// Checks prerequisites:
  /// - Returns if no active segment is detected
  /// - Skips if the current segment has already been captured
  /// - Skips if a capture is in progress
  ///
  /// Otherwise, calls [_updateMessageSegment] to determine the appropriate message.
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

  /// Clears the current message and hides the tooltip.
  void clearMessage() {
    _setMessage(null);
  }

  /// Determines and sets the guidance message for a specific segment.
  ///
  /// Checks for required car parts in the segmentation:
  /// 1. If license plate is missing: shows initial segment-specific guide
  /// 2. If door is missing: shows "move back" guide
  /// 3. If all required parts detected: shows "hold still" guide and triggers auto-capture
  ///
  /// Parameters:
  ///   - classes: Set of detected class names from segmentation
  ///   - segmentIndex: The current segment (0-3) being processed
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

  /// Updates the current message and notifies listeners if the message changed.
  ///
  /// Skips notification if the message is identical to the current one.
  ///
  /// Parameters:
  ///   - msg: The new guidance message to display
  void _setMessage(CameraMessage? msg) {
    if (_message == msg) return;
    _message = msg;
    notifyListeners();
  }

  /// Automatically captures a photo and displays a success message.
  ///
  /// Called when all required car parts are detected in the current segment.
  Future<void> _triggerAutoCapture() async {
    await capturePhoto();
    if (_activeSegmentIndex != null) {
      _panoramicCapturedSegments.add(_activeSegmentIndex!);
    }
    _classificationLocked = true;
    _setMessage(CameraMessage(
      message: StringSheet.inspectDamageGuide,
      type: MessageType.info,
    ));
  }

  /// Đánh dấu góc hiện tại hoàn thành và unlock classification sang góc tiếp theo.
  void completeCurrentAngle() {
    if (_activeSegmentIndex == null) return;
    _completedSegments.add(_activeSegmentIndex!);
    _panoramicCapturedSegments.remove(_activeSegmentIndex!);
    _classificationLocked = false;
    _setMessage(null);
  }

  /// Cleanup method called when the controller is disposed.
  ///
  /// Ensures the torch is turned off before disposal.
  @override
  void dispose() {
    // stop() sends 'stop' to native synchronously via MethodChannel fire-and-forget.
    // The native handler nils all CoreML predictors immediately, freeing GPU/ANE memory
    // before _MultiTaskYOLOViewState.dispose() detaches the channel.
    yoloController.stop();
    super.dispose();
  }
}
