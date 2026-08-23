part of 'camera_controller.dart';

/// Chụp & lưu ảnh xuống disk cache, giữ file path trong memory và khôi phục từ
/// cache.
mixin _CaptureMixin on _CameraControllerBase {
  // ── Cache restore ─────────────────────────────────────────────────────────

  /// Restores previously captured photos from disk cache.
  /// Call once after construction; notifies listeners when done.
  Future<void> loadCachedPhotos() async {
    final cached =
        await PhotoSessionCache.instance.loadSessionPhotoPaths(_sessionId);
    if (cached.isEmpty) return;
    _capturedPhotos = cached;
    // Angles with cached photos are shown as completed in the progress ring.
    _completedSegments.addAll(cached.keys);
    _panoramicCapturedSegments.addAll(cached.keys);
    _firstPanoramicCaptured = cached.isNotEmpty;
    notifyListeners();
  }

  // ── Photo capture ─────────────────────────────────────────────────────────

  /// Captures a burst (pre-roll + anchor + post-roll on iOS), writes frames to
  /// disk and enqueues them for background upload.
  /// Does NOT modify [_completedSegments] in 4-angle mode — completion happens
  /// when the classifier detects that the user moved to another car angle.
  @override
  Future<String?> capturePhoto({
    bool immediate = false,
    int? segment,
    bool flashTick = true,
  }) async {
    if (_isCapturing) return null;
    _isCapturing = true;
    notifyListeners();
    try {
      /// Chụp tự động quá nhanh, người dùng chưa kịp đọc message -> delay 3s.
      /// Chụp thủ công ([immediate]) thì chụp ngay.
      if (!immediate) await Future.delayed(const Duration(seconds: 3));
      if (flashTick) _captureFlashTick++;
      _flashCornerSuccess(_captureFreezeDuration);

      final seg = segment ?? _activeSegmentIndex;
      if (seg == null) return null;

      if (Platform.isIOS) {
        final dir = await PhotoSessionCache.instance.createBurstDir(_sessionId);

        // Phase 1: capture anchor photo only (~200ms).
        // Freeze overlay starts immediately — same UX as before burst was added.
        final anchor = await yoloController.captureBurstAnchor(
          dirPath: dir,
          cropTop: _cropTop,
          cropBottom: _cropBottom,
          quality: 80,
        );
        if (anchor == null) return null;

        _capturedPhotos.putIfAbsent(seg, () => []).add(anchor.filePath);
        if (!_require4Angles) _completedSegments.add(seg);
        _startCaptureFreeze(anchor.filePath);

        // Enqueue anchor immediately so it uploads first — Host App receives
        // the onImageUploaded callback as fast as the old single-photo path.
        await PhotoUploadQueue.instance.enqueuePhoto(
          sessionId: _sessionId,
          angleId: seg,
          photoIndex: anchor.stepIndex,
          filePath: anchor.filePath,
          imageOrder: anchor.stepIndex,
          isCallEngine: true,
        );

        // Phase 2: collect post-roll + enqueue surrounding burst frames in
        // background (~2.5s). Anchor is excluded (already enqueued above).
        unawaited(_awaitAndEnqueueBurstFrames(
          angleId: seg,
          anchorFilePath: anchor.filePath,
        ));

        return anchor.filePath;
      }

      // Android: two-phase burst (same as iOS).
      final dir = await PhotoSessionCache.instance.createBurstDir(_sessionId);

      // Phase 1: capture anchor photo only (~200ms).
      // Freeze overlay starts immediately — same UX as before burst was added.
      final anchor = await yoloController.captureBurstAnchor(
        dirPath: dir,
        cropTop: _cropTop,
        cropBottom: _cropBottom,
        quality: 80,
      );
      if (anchor == null) return null;

      _capturedPhotos.putIfAbsent(seg, () => []).add(anchor.filePath);
      if (!_require4Angles) _completedSegments.add(seg);
      _startCaptureFreeze(anchor.filePath);

      // Enqueue anchor immediately so it uploads first.
      await PhotoUploadQueue.instance.enqueuePhoto(
        sessionId: _sessionId,
        angleId: seg,
        photoIndex: anchor.stepIndex,
        filePath: anchor.filePath,
        imageOrder: anchor.stepIndex,
        isCallEngine: true,
      );

      // Phase 2: collect post-roll + enqueue surrounding burst frames in
      // background (~2.5s). Anchor is excluded (already enqueued above).
      unawaited(_awaitAndEnqueueBurstFrames(
        angleId: seg,
        anchorFilePath: anchor.filePath,
      ));

      return anchor.filePath;
    } catch (_) {
      return null;
    } finally {
      await _awaitCaptureFreeze();
      _isCapturing = false;
      if (!_stopped) notifyListeners();
    }
  }

  /// Awaits native post-roll completion then enqueues the surrounding burst
  /// frames (pre-roll + post-roll) for background upload.  The anchor photo
  /// identified by [anchorFilePath] is skipped because it was already enqueued
  /// in Phase 1 of [capturePhoto].
  /// Fire-and-forget from [capturePhoto]; errors are logged but not re-thrown.
  Future<void> _awaitAndEnqueueBurstFrames({
    required int angleId,
    required String anchorFilePath,
  }) async {
    try {
      final frames = await yoloController.captureBurstAwaitPostRoll();
      if (frames.isEmpty) return;
      // Anchor already enqueued in Phase 1 — only enqueue surrounding frames.
      final burstOnly =
          frames.where((f) => f.filePath != anchorFilePath).toList();
      if (burstOnly.isEmpty) return;
      await _enqueueBurstFrames(burstOnly, angleId: angleId);
    } catch (error, stackTrace) {
      debugPrint('AICycle burst post-roll enqueue failed: $error\n$stackTrace');
    }
  }

  Future<void> _enqueueBurstFrames(
    List<BurstFrameInfo> frames, {
    required int angleId,
  }) async {
    try {
      final sorted = [...frames]
        ..sort((a, b) => a.stepIndex.compareTo(b.stepIndex));
      for (final frame in sorted) {
        await PhotoUploadQueue.instance.enqueuePhoto(
          sessionId: _sessionId,
          angleId: angleId,
          photoIndex: frame.stepIndex,
          filePath: frame.filePath,
          imageOrder: frame.stepIndex,
          isCallEngine: frame.isCallEngine,
        );
      }
      await PhotoUploadQueue.instance.schedulePendingUploads();
    } catch (error, stackTrace) {
      debugPrint('AICycle burst enqueue failed: $error\n$stackTrace');
    }
  }

  /// Chụp thủ công bằng nút shutter: chụp ngay, lưu vào góc đang active (mặc
  /// định góc 0 nếu chưa phân loại được góc).
  Future<void> manualCapture() async {
    final shouldContinueAfterCapture =
        _message?.message == StringSheet.noDamageDetectedGuide;
    final captured = await capturePhoto(
      immediate: true,
      segment: _activeSegmentIndex ?? 0,
    );
    if (captured == null || !shouldContinueAfterCapture || _stopped) return;
    await _showManualCaptureContinueGuide();
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
}
