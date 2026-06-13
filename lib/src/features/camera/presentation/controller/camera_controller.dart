import 'package:aicycle_yolo/multi_task_yolo_view.dart';
import 'package:flutter/foundation.dart';

class CameraController extends ChangeNotifier {
  final yoloController = MultiTaskYOLOController();

  bool _torchEnabled = false;
  int _capturedCount = 0;
  bool _isCapturing = false;
  List<Uint8List> _capturedPhotos = [];

  bool get isTorchEnabled => _torchEnabled;
  bool get isCapturing => _isCapturing;
  List<Uint8List> get capturedPhotos => _capturedPhotos;

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
      _capturedCount++;
      _capturedPhotos.add(bytes);
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
    // Torch off khi rời màn hình
    if (_torchEnabled) yoloController.setTorch(false);
    super.dispose();
  }
}
