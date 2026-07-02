part of 'camera_controller.dart';

/// Canh khung ảnh toàn cảnh: theo bộ phận (carPart) + OCR biển số, và tự động
/// chụp ảnh toàn cảnh khi biển số đọc được.
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
    if (_completedSegments.contains(_activeSegmentIndex)) return;
    if (_panoramicCapturedSegments.contains(_activeSegmentIndex)) return;
    if (_isCapturing) return;
    _updateMessageSegment(_latestCarPartClasses, _activeSegmentIndex!);
  }

  void _updateMessageSegment(Set<String> classes, int segmentIndex) {
    const licencePlate = _licensePlateClass;
    const door = 'Cánh cửa';

    final config = _segmentConfigs[segmentIndex];
    if (config == null) return;

    final (frontBumper, initialGuide) = config;

    final hasPlate = classes.contains(licencePlate);
    final allPresent =
        hasPlate && classes.contains(door) && classes.contains(frontBumper);

    // Chỉ giữ timer 5s khi đang ở trạng thái "đã căn đủ, chờ OCR". Rời trạng
    // thái này (di chuyển làm mất bộ phận) → huỷ timer + reset cờ nhắc.
    if (!(allPresent && !_latestPlateReadable)) {
      _cancelPlateReadTimer();
    }
    // Rời trạng thái căn đủ → reset mốc đếm thời gian giữ yên.
    if (!allPresent) {
      _holdStillShownAt = null;
    }

    if (!hasPlate) {
      _setMessage(
          CameraMessage(message: initialGuide, type: MessageType.guide));
    } else if (!classes.contains(door)) {
      _setMessage(CameraMessage(
          message: StringSheet.moveBackGuide, type: MessageType.info));
    } else if (allPresent) {
      // Bộ phận đã căn đủ — giữ yên để OCR đọc biển số. Chỉ chụp ảnh toàn cảnh
      // khi OCR đọc được biển (khung đủ rõ/đủ gần), tránh chụp ảnh mờ/xa.
      _holdStillShownAt ??= DateTime.now();
      // Giữ message "giữ yên" tối thiểu 3s trước khi auto-capture, kể cả khi OCR
      // đọc được biển ngay — để user kịp thấy hướng dẫn.
      final heldLongEnough = DateTime.now().difference(_holdStillShownAt!) >=
          _holdStillMinDuration;
      if (_latestPlateReadable && heldLongEnough) {
        _triggerAutoCapture();
      } else if (_platePromptShown) {
        // Quá 5s vẫn chưa đọc được biển → giữ nhắc di chuyển cho biển rõ nét.
        _setMessage(CameraMessage(
            message: StringSheet.movePlateClearGuide,
            type: MessageType.warning));
      } else {
        _setMessage(CameraMessage(
            message: StringSheet.holdStillGuide, type: MessageType.loading));
        _ensurePlateReadTimer();
      }
    }
  }

  /// Bắt đầu đếm 5s chờ OCR (nếu chưa chạy). Hết 5s mà chưa đọc được biển →
  /// bật cờ nhắc + hiển thị message di chuyển cho biển rõ.
  void _ensurePlateReadTimer() {
    if (_plateReadTimer != null) return;
    _plateReadTimer = Timer(const Duration(seconds: 5), () {
      _plateReadTimer = null;
      _platePromptShown = true;
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
  }

  Future<void> _triggerAutoCapture() async {
    // Cờ "đọc được biển" chỉ dùng cho 1 lần chụp toàn cảnh; reset để góc sau
    // phải đọc lại biển mới chụp.
    _latestPlateReadable = false;
    _holdStillShownAt = null;
    _cancelPlateReadTimer();
    // OCR vừa đọc được biển ở frame hiện tại ⇒ chụp NGAY (immediate, bỏ delay 3s)
    // để ảnh toàn cảnh sát nhất với frame đã canh đúng khung + đọc được biển.
    await capturePhoto(immediate: true);
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
    _setMessage(CameraMessage(
      message: StringSheet.plateValidCaptured,
      type: MessageType.success,
    ));
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
