part of 'camera_controller.dart';

/// Upload ngầm 1 frame preview/giây trong pha inspection để BE có context
/// trước/sau ảnh tổn thất sát crop.
mixin _ContextStreamMixin on _CameraControllerBase {
  bool _contextStreamActive = false;

  @override
  Future<void> _startContextStream() async {
    if (_stopped || _contextStreamActive) return;
    final dir = await PhotoSessionCache.instance.streamDirPath(_sessionId);
    await yoloController.startContextStream(dirPath: dir);
    _contextStreamActive = true;
  }

  @override
  Future<void> _stopContextStream() async {
    if (!_contextStreamActive) return;
    _contextStreamActive = false;
    await yoloController.stopContextStream();
  }

  @override
  void _onContextStreamFrame(String filePath) {
    if (_stopped || _inspectionPhase == null || _isCapturing) return;
    final order = ++_imageOrderCounter;
    unawaited(
      PhotoUploadQueue.instance.enqueuePhoto(
        sessionId: _sessionId,
        angleId: _activeSegmentIndex ?? 0,
        photoIndex: order,
        filePath: filePath,
        imageOrder: order,
        isCallEngine: false,
      ),
    );
  }
}
