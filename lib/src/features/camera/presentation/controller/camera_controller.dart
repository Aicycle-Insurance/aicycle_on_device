import 'package:aicycle_yolo/multi_task_yolo_view.dart';
import 'package:flutter/foundation.dart';

import '../../data/model/car_angle.dart';
import '../../data/model/classify_output.dart';

class CameraController extends ChangeNotifier {
  final yoloController = MultiTaskYOLOController();

  bool _torchEnabled = false;
  bool _isCapturing = false;
  List<Uint8List> _capturedPhotos = [];

  /// Segment index (0–3) đang được detect, null nếu chưa nhận kết quả.
  int? _activeSegmentIndex;

  /// Các segment đã chụp xong.
  final Set<int> _completedSegments = {};

  bool get isTorchEnabled => _torchEnabled;
  bool get isCapturing => _isCapturing;
  List<Uint8List> get capturedPhotos => _capturedPhotos;
  int? get activeSegmentIndex => _activeSegmentIndex;
  Set<int> get completedSegments => Set.unmodifiable(_completedSegments);

  /// Gọi từ [MultiTaskYOLOView.onStreamingData].
  void onStreamingData(Map<String, dynamic> data) {
    if (data['type'] != 'classify') return;
    final output = ClassifyOutput.fromJson(Map<String, dynamic>.from(data));
    final segment = CarAngle.segmentOf(output.classification.top1);
    if (segment == _activeSegmentIndex) return;
    _activeSegmentIndex = segment;
    notifyListeners();
  }

  Future<void> toggleFlash() async {
    final actual = await yoloController.setTorch(!_torchEnabled);
    _torchEnabled = actual;
    notifyListeners();
  }

  Future<Uint8List?> capturePhoto() async {
    if (_isCapturing) return null;
    _isCapturing = true;
    notifyListeners();
    try {
      final bytes = await yoloController.capturePhoto();
      _capturedPhotos.add(bytes);
      // Đánh dấu segment hiện tại là đã chụp
      if (_activeSegmentIndex != null) {
        _completedSegments.add(_activeSegmentIndex!);
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

  @override
  void dispose() {
    if (_torchEnabled) yoloController.setTorch(false);
    super.dispose();
  }
}
