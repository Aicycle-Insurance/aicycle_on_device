part of 'camera_controller.dart';

/// Máy trạng thái soi tổn thất sau khi đã chụp ảnh toàn cảnh:
/// scanning → detectionReady → capturingDamage → detailGuide → continueOrChange.
mixin _InspectionMixin on _CameraControllerBase {
  /// Bắt đầu (hoặc quay lại) trạng thái scanning: detection chạy theo sự kiện,
  /// không tự rời góc khi chưa thấy tổn thất.
  @override
  void startDamageScanning() => _enterScanning();

  void _enterScanning() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _detailTimer?.cancel();
    _detailTimer = null;
    // Quay lại quét ảnh tổng quan → reset trạng thái chụp ảnh chi tiết.
    _inDetailStage = false;
    // Vào pha quét thiệt hại → bật carDamage (carCorner/carPart vẫn bật).
    _setInspectionPhase(InspectionPhase.scanning);
    _setMessage(null);
    _startNoDetectionWarningTimer();
  }

  /// Khi đang quét (scanning) mà phát hiện tổn thất → hiển thị xác nhận ngay.
  /// Pha detailGuide KHÔNG short-circuit ở đây: nó chờ đủ 10 s (cho user lại gần)
  /// rồi mới tự đánh giá trong [_onDetailTimeout]. An toàn khi gọi nhiều lần.
  @override
  void _maybeShowDetectionReady() {
    if (_latestDetections.isEmpty) return;

    // Vừa chụp toàn cảnh xong (đang ở màn hướng dẫn) mà đã phát hiện tổn thất
    // → vào scanning luôn. Riêng continueOrChange phải giữ đủ thời gian để user
    // đọc được "Tiếp tục di chuyển..." / "Hãy đưa camera lại gần..." rồi mới quét.
    if (_inspectionPhase == InspectionPhase.panoramicGuide) {
      _enterScanning();
    }

    if (_inspectionPhase != InspectionPhase.scanning) return;
    _enterDetectionReady();
  }

  /// Chuyển sang detectionReady: hiện xác nhận tổn thất + mở timer 10 s chụp ngầm.
  /// Dùng cho cả ảnh tổng quan (từ scanning) và ảnh chi tiết (từ detailGuide).
  /// [_inDetailStage] do bên gọi quyết định.
  void _enterDetectionReady() {
    _cancelNoDetectionWarningTimer();
    _detailTimer?.cancel();
    _detailTimer = null;
    _setInspectionPhase(InspectionPhase.detectionReady);
    _setMessage(CameraMessage(
      message: StringSheet.damageDetectedGuide,
      type: MessageType.info,
    ));
    // Cứ mỗi 10 s không bấm gì → tự động chụp ngầm, nhưng vẫn giữ tooltip xác
    // nhận cho tới khi user bấm "Xác nhận" hoặc "Thiếu tổn thất".
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = Timer.periodic(_damageAutoCaptureInterval, (timer) {
      if (_inspectionPhase != InspectionPhase.detectionReady) {
        timer.cancel();
        return;
      }
      capturePhoto(immediate: true, flashTick: false);
    });
  }

  /// Các pha đang chờ phát hiện tổn thất: hướng dẫn soi (panoramicGuide) và
  /// đang quét (scanning). Hết 10 s mà không thấy tổn thất → chỉ hiện warning,
  /// không tự rời góc.
  bool get _isAwaitingDamageWarning =>
      _inspectionPhase == InspectionPhase.scanning ||
      _inspectionPhase == InspectionPhase.panoramicGuide;

  @override
  void _startNoDetectionWarningTimer() {
    _noDetectionWarningTimer?.cancel();
    _noDetectionWarningTimer =
        Timer(const Duration(seconds: 10), _onNoDetectionWarningTimeout);
  }

  void _cancelNoDetectionWarningTimer() {
    _noDetectionWarningTimer?.cancel();
    _noDetectionWarningTimer = null;
  }

  void _onNoDetectionWarningTimeout() {
    _noDetectionWarningTimer = null;
    if (!_isAwaitingDamageWarning) return;
    if (_latestDetections.isNotEmpty) return;

    _setMessage(CameraMessage(
      message: StringSheet.noDamageDetectedGuide,
      type: MessageType.warning,
    ));
  }

  /// User pressed "Thiếu tổn thất" — không chụp, hiện nhắc đưa camera lại gần
  /// tổn thất còn thiếu rồi quay lại scanning (về lại bước ảnh tổng quan).
  void rejectDamage() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _cancelNoDetectionWarningTimer();
    _showMessageThenScan(
      StringSheet.moveCameraToMissing,
      duration: const Duration(seconds: 10),
    );
  }

  /// User pressed "Xác nhận" (hoặc auto sau 10 s) — chụp ảnh tổn thất.
  ///   - Nếu vừa chụp ảnh TỔNG QUAN → sang pha [detailGuide] để chụp ảnh chi tiết.
  ///   - Nếu vừa chụp ảnh CHI TIẾT → nhắc "Tiếp tục di chuyển camera…" rồi quét tiếp.
  Future<void> confirmDamage({bool flashTick = true}) async {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _cancelNoDetectionWarningTimer();
    final wasDetail = _inDetailStage;
    _setInspectionPhase(InspectionPhase.capturingDamage);

    final captured = await capturePhoto(immediate: true, flashTick: flashTick);
    if (captured != null) {
      _setMessage(CameraMessage(
        message: StringSheet.captureSuccess,
        type: MessageType.success,
      ));
      await Future.delayed(_captureSuccessVisibleDuration);
      if (_stopped) return;
    }

    if (wasDetail) {
      await _showMessageThenScan(StringSheet.continueToNextDamage);
    } else {
      _enterDetailGuide();
    }
  }

  // ── Detail-photo stage ─────────────────────────────────────────────────────

  /// Sau khi chụp ảnh tổng quan: nhắc user lại gần để chụp ảnh chi tiết. Sau
  /// 10 s chưa nhận diện thì tự chụp một ảnh; sau thêm 5 s vẫn chưa nhận diện
  /// thì chuyển sang hướng dẫn tiếp tục di chuyển.
  void _enterDetailGuide() {
    _cancelNoDetectionWarningTimer();
    _inDetailStage = true;
    _setInspectionPhase(InspectionPhase.detailGuide);
    _setMessage(CameraMessage(
      message: StringSheet.detailPhotoGuide,
      type: MessageType.info,
    ));
    _startDetailTimer();
  }

  void _startDetailTimer() {
    _detailTimer?.cancel();
    _detailTimer = Timer(_detailAutoCaptureDelay, _onDetailTimeout);
  }

  /// Hết 10 s ở pha detailGuide:
  ///   - Nếu đang có tổn thất trong khung → mở xác nhận ảnh chi tiết.
  ///   - Nếu chưa thấy tổn thất → chụp ngầm 1 ảnh chi tiết rồi chờ thêm 5 s.
  Future<void> _onDetailTimeout() async {
    _detailTimer = null;
    if (_inspectionPhase != InspectionPhase.detailGuide) return;

    if (_latestDetections.isNotEmpty) {
      // _inDetailStage đang true → sau khi xác nhận sẽ sang "Tiếp tục di chuyển".
      _enterDetectionReady();
      return;
    }

    await capturePhoto(immediate: true, flashTick: false);
    // Trong lúc chụp, frame mới có thể đã đổi pha (vd phát hiện tổn thất).
    if (_inspectionPhase != InspectionPhase.detailGuide) return;
    _startDetailPostCaptureTimer();
  }

  void _startDetailPostCaptureTimer() {
    _detailTimer?.cancel();
    _detailTimer = Timer(
      _detailPostCaptureNoDetectionDelay,
      _onDetailPostCaptureTimeout,
    );
  }

  Future<void> _onDetailPostCaptureTimeout() async {
    _detailTimer = null;
    if (_inspectionPhase != InspectionPhase.detailGuide) return;

    if (_latestDetections.isNotEmpty) {
      _enterDetectionReady();
      return;
    }

    await _showMessageThenScan(StringSheet.continueToNextDamage);
  }

  /// Hiển thị [message] đủ thời gian rồi quay lại scanning. Detection mới trong
  /// lúc message đang hiển thị không ghi đè ngay, tránh user không kịp đọc.
  /// Dùng cho cả "Tiếp tục di chuyển camera…" và "Thiếu tổn thất".
  Future<void> _showMessageThenScan(
    String message, {
    Duration duration = const Duration(seconds: 5),
  }) async {
    _cancelNoDetectionWarningTimer();
    _detailTimer?.cancel();
    _detailTimer = null;
    _setInspectionPhase(InspectionPhase.continueOrChange);
    _setMessage(CameraMessage(message: message, type: MessageType.info));

    await Future.delayed(duration);
    // Guard: flow có thể đã tự chuyển góc trong lúc chờ.
    if (_inspectionPhase != InspectionPhase.continueOrChange) return;
    _enterScanning();
    if (_latestDetections.isNotEmpty) _enterDetectionReady();
  }

  @override
  Future<void> _showManualCaptureContinueGuide() =>
      _showMessageThenScan(StringSheet.continueToNextDamage);

  /// Rời góc hiện tại — thoát inspection, mở khoá classification.
  /// Giữ angle trong [_panoramicCapturedSegments] để khi quay lại sẽ vào
  /// thẳng scanning (không chụp toàn cảnh lại).
  ///
  /// Sau khi hoàn thành ở flow 4-góc, hiển thị message điều hướng tới góc chưa
  /// hoàn thành tiếp theo theo thứ tự 0 → 1 → 2 → 3. Khi 4-góc tắt,
  /// `_completedSegments` chỉ phản ánh góc đã có ảnh, không phải góc classifier
  /// từng đi qua.
  void completeCurrentAngle() {
    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _cancelNoDetectionWarningTimer();
    _detailTimer?.cancel();
    _detailTimer = null;
    _inDetailStage = false;
    final justCompleted = _activeSegmentIndex;
    if (justCompleted != null && _require4Angles) {
      _completedSegments.add(justCompleted);
    }
    _classificationLocked = false;
    _resetPanoramicFramingState(clearCarParts: true);
    // Quay lại chọn góc → tắt carDamage (carCorner/carPart vẫn bật).
    _setInspectionPhase(null);

    // Config 4 góc TẮT: không điều hướng "di chuyển về góc chéo …" — user tự do
    // di chuyển ghi nhận tổn thất ở góc bất kỳ.
    final nextSegment =
        _require4Angles ? _nextNavigationSegment(justCompleted) : null;
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

  bool get _canAutoSwitchAngle =>
      _inspectionPhase == InspectionPhase.panoramicGuide ||
      _inspectionPhase == InspectionPhase.scanning ||
      _inspectionPhase == InspectionPhase.continueOrChange;

  @override
  void _autoSwitchToDetectedSegment(int segment) {
    if (!_classificationLocked) return;
    if (!_canAutoSwitchAngle) return;
    if (segment == _activeSegmentIndex) return;

    _autoCaptureTimer?.cancel();
    _autoCaptureTimer = null;
    _cancelNoDetectionWarningTimer();
    _detailTimer?.cancel();
    _detailTimer = null;
    _inDetailStage = false;

    final previousSegment = _activeSegmentIndex;
    if (previousSegment != null && _require4Angles) {
      _completedSegments.add(previousSegment);
    }

    _setInspectionPhase(null);
    _classificationLocked = false;
    _activeSegmentIndex = segment;
    _resetPanoramicFramingState(clearCarParts: true);

    final skipPanoramic = _panoramicCapturedSegments.contains(segment) ||
        (!_require4Angles && _firstPanoramicCaptured);
    if (skipPanoramic) {
      _classificationLocked = true;
      startDamageScanning();
    } else {
      updateMessage();
    }
  }
}
