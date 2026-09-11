part of 'camera_controller.dart';

/// Canh khung ảnh toàn cảnh theo bộ phận (carPart) + OCR biển số.
///
/// Đủ bộ phận → hiện "Hãy giữ yên điện thoại…" → đúng [_holdStillMinDuration]
/// sau là CHẮC CHẮN chụp ([_CameraControllerBase._syncHoldStillCaptureTimer]).
/// OCR không còn là điều kiện chụp: tooltip đã hiện là đã hứa với user.
mixin _PanoramicMixin on _CameraControllerBase {
  @override
  Future<void> updateMessage() async {
    if (_activeSegmentIndex == null) {
      _setMessage(null);
      return;
    }
    // Message canh ảnh toàn cảnh chỉ áp dụng trước khi vào inspection. Khi đã
    // ở pha inspection (vd config 4 góc tắt: góc khác vào thẳng scanning mà
    // không nằm trong _panoramicCapturedSegments) thì không ghi đè message
    // scanning bằng hướng dẫn canh khung/"di chuyển về góc chéo".
    if (_inspectionPhase != null) return;
    // Đã hiện "Hãy giữ yên điện thoại…" ⇒ đã hứa 3s nữa sẽ chụp. Giữ nguyên
    // message tới lúc chụp: bộ phận rời khung cũng không được đổi sang hướng dẫn
    // khác, vì đổi message sẽ huỷ hẹn chụp.
    if (_holdStillCapturePending) return;
    if (_completedSegments.contains(_activeSegmentIndex)) return;
    if (_panoramicCapturedSegments.contains(_activeSegmentIndex)) return;
    if (_isCapturing) return;
    _updateMessageSegment(_activeSegmentIndex!);
  }

  void _updateMessageSegment(int segmentIndex) {
    const licencePlate = _licensePlateClass;
    const door = 'Cánh cửa';

    final config = _segmentConfigs[segmentIndex];
    if (config == null) return;

    final (frontBumper, initialGuide) = config;

    // Presence đã làm mượt qua _carPartFlickerGrace — một frame detect nhiễu
    // (mất bộ phận 1-2 frame) không reset đồng hồ giữ yên / đổi message.
    final hasPlate = _seenRecently(licencePlate);
    final hasDoor = _seenRecently(door);
    final allPresent = hasPlate && hasDoor && _seenRecently(frontBumper);

    if (!hasPlate) {
      _setMessage(
          CameraMessage(message: initialGuide, type: MessageType.guide));
    } else if (!hasDoor) {
      _setMessage(CameraMessage(
          message: StringSheet.moveBackGuide, type: MessageType.info));
    } else if (allPresent) {
      // Bộ phận đã căn đủ → hiện "Hãy giữ yên điện thoại…".
      // [_syncHoldStillCaptureTimer] hẹn giờ ngay khi tooltip thật sự hiện và
      // chụp sau đúng [_holdStillMinDuration].
      _setMessage(CameraMessage(
          message: StringSheet.holdStillGuide, type: MessageType.loading));
    }
  }

  @override
  Future<void> _triggerAutoCapture() async {
    _resetAutoCaptureFramingState();
    // Nhịp chờ 3s đã nằm ở [_holdStillCaptureTimer] rồi ⇒ chụp NGAY (immediate,
    // bỏ delay 3s trong capturePhoto), tránh cộng dồn thành 6s.
    await capturePhoto(immediate: true);
    // Chụp mất vài trăm ms; mọi thứ dưới đây đều notify hoặc đổi state.
    if (_stopped) return;
    await _afterAutoCaptureSuccess();
  }

  /// Debug: inject ảnh gallery như một lượt auto-capture (bypass framing).
  @override
  Future<void> injectGalleryPhotoAsAutoCapture(String sourcePath) async {
    if (!_debugMode || _isCapturing) return;
    _resetAutoCaptureFramingState();
    final seg = _activeSegmentIndex ?? 0;
    final path = await capturePhotoFromGallery(sourcePath, segment: seg);
    if (path == null || _stopped) return;
    await _afterAutoCaptureSuccess(segment: seg);
  }

  void _resetAutoCaptureFramingState() {
    // Reset trạng thái framing nếu cần trước lần chụp kế tiếp
  }

  Future<void> _afterAutoCaptureSuccess({int? segment}) async {
    final seg = segment ?? _activeSegmentIndex;
    if (seg != null) {
      _panoramicCapturedSegments.add(seg);
      // Chụp toàn cảnh xong là góc đó đã được tính hoàn thành.
      _completedSegments.add(seg);
    }
    // Mốc ảnh toàn cảnh đầu tiên đã xong → khi config 4 góc tắt, các góc sau
    // vào thẳng scanning.
    _firstPanoramicCaptured = true;
    _classificationLocked = true;
    // Đã chụp toàn cảnh thành công → báo thành công 3s rồi mới sang pha inspection.
    // (Segment đã nằm trong _panoramicCapturedSegments nên updateMessage bị chặn
    // → message thành công không bị frame carPart kế tiếp ghi đè.)
    _setMessage(
      CameraMessage(
        message: StringSheet.captureSuccess,
        type: MessageType.success,
      ),
      immediate: true,
    );
    await Future.delayed(const Duration(seconds: 3));
    if (_stopped) return;
    _setInspectionPhase(InspectionPhase.panoramicGuide);
    _setMessage(CameraMessage(
      message: StringSheet.inspectDamageGuide,
      type: MessageType.info,
    ));
    _startNoDetectionWarningTimer();
  }
}
