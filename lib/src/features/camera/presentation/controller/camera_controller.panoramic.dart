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
    final plateReadable = _hasFreshPlateRead;
    final now = DateTime.now();
    if (_platePromptShown) _platePromptShownAt ??= now;
    final platePromptVisibleLongEnough = !_platePromptShown ||
        now.difference(_platePromptShownAt!) >= _plateClearPromptMinDuration;
    final keepPlatePromptVisible =
        allPresent && _platePromptShown && !platePromptVisibleLongEnough;

    // Chỉ giữ timer nhắc khi đang ở trạng thái "đã căn đủ, chờ OCR". Rời trạng
    // thái này (di chuyển làm mất bộ phận) → huỷ timer + reset cờ nhắc. Nếu
    // warning căn biển rõ vừa xuất hiện thì giữ tối thiểu một nhịp, kể cả khi OCR đã
    // đọc lại được biển.
    if (!(allPresent && (!plateReadable || keepPlatePromptVisible))) {
      _cancelPlateReadTimer();
    }

    if (!hasPlate) {
      _setMessage(
          CameraMessage(message: initialGuide, type: MessageType.guide));
    } else if (!hasDoor) {
      _setMessage(CameraMessage(
          message: StringSheet.moveBackGuide, type: MessageType.info));
    } else if (allPresent) {
      // Bộ phận đã căn đủ → hiện "Hãy giữ yên điện thoại…". Nhánh này KHÔNG
      // quyết định thời điểm chụp: [_syncHoldStillCaptureTimer] hẹn giờ ngay khi
      // tooltip thật sự hiện và chụp sau đúng [_holdStillMinDuration], dù sau đó
      // bộ phận rời khung, OCR không đọc được biển, hay stream ngừng bắn frame.
      //
      // LƯU Ý: vì lời hứa 3s là tuyệt đối và [_plateReadPromptDelay] (5s) dài
      // hơn, nhắc "biển số chưa rõ" bên dưới hiện KHÔNG BAO GIỜ chạy tới — giữ
      // lại để dễ khôi phục nếu muốn chụp có điều kiện OCR trở lại.
      if (_platePromptShown) {
        // Chưa đọc được biển → giữ nhắc di chuyển cho biển rõ nét.
        _setMessage(CameraMessage(
            message: StringSheet.movePlateClearGuide,
            type: MessageType.warning));
      } else {
        _setMessage(CameraMessage(
            message: StringSheet.holdStillGuide, type: MessageType.loading));
        if (_holdStillGuideShownAt != null) _ensurePlateReadTimer();
      }
    }
  }

  /// Bắt đầu đếm chờ OCR (nếu chưa chạy). Hết thời gian mà chưa đọc được biển →
  /// bật cờ nhắc + hiển thị message di chuyển cho biển rõ.
  void _ensurePlateReadTimer() {
    if (_plateReadTimer != null) return;
    _plateReadTimer = Timer(_plateReadPromptDelay, () {
      _plateReadTimer = null;
      _platePromptShown = true;
      _platePromptShownAt = DateTime.now();
      _setMessage(CameraMessage(
        message: StringSheet.movePlateClearGuide,
        type: MessageType.warning,
      ));
    });
  }

  void _cancelPlateReadTimer() {
    _plateReadTimer?.cancel();
    _plateReadTimer = null;
    _platePromptShown = false;
    _platePromptShownAt = null;
  }

  @override
  Future<void> _triggerAutoCapture() async {
    // Cờ "đọc được biển" chỉ dùng cho 1 lần chụp toàn cảnh; reset để góc sau
    // phải đọc lại biển mới chụp.
    _clearPlateRead();
    _platePromptShownAt = null;
    _cancelPlateReadTimer();
    // Nhịp chờ 3s đã nằm ở [_holdStillCaptureTimer] rồi ⇒ chụp NGAY (immediate,
    // bỏ delay 3s trong capturePhoto), tránh cộng dồn thành 6s.
    await capturePhoto(immediate: true);
    // Chụp mất vài trăm ms; mọi thứ dưới đây đều notify hoặc đổi state.
    if (_stopped) return;
    if (_activeSegmentIndex != null) {
      _panoramicCapturedSegments.add(_activeSegmentIndex!);
      // Chụp toàn cảnh xong là góc đó đã được tính hoàn thành.
      _completedSegments.add(_activeSegmentIndex!);
    }
    // Mốc ảnh toàn cảnh đầu tiên đã xong → khi config 4 góc tắt, các góc sau
    // vào thẳng scanning.
    _firstPanoramicCaptured = true;
    _classificationLocked = true;
    // Biển hợp lệ + đã chụp → báo thành công 3s rồi mới sang pha inspection.
    // (Segment đã nằm trong _panoramicCapturedSegments nên updateMessage bị chặn
    // → message thành công không bị frame carPart kế tiếp ghi đè.)
    _setMessage(
      CameraMessage(
        message: StringSheet.plateValidCaptured,
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
