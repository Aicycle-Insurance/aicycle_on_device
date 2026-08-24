part of 'camera_controller.dart';

/// Chụp & lưu ảnh xuống disk cache, giữ file path trong memory và khôi phục từ
/// cache.
mixin _CaptureMixin on _CameraControllerBase {
  // ── Cache restore ─────────────────────────────────────────────────────────

  /// Restores previously captured photos from disk cache.
  /// Call once after construction; notifies listeners when done.
  /// Restores previously captured photos from disk cache.
  /// Call once after construction; notifies listeners when done.
  Future<void> loadCachedPhotos() async {
    // Pre-fetch GPS position in background when camera session initializes
    unawaited(LocationService().getFastCurrentPosition());

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

      // Lấy vị trí GPS nhanh tại thời điểm chụp ảnh Anchor
      double? latitude;
      double? longitude;
      final posResult = await LocationService().getFastCurrentPosition();
      posResult.fold(
        (_) {},
        (pos) {
          latitude = pos.latitude;
          longitude = pos.longitude;
        },
      );

      final dir = await PhotoSessionCache.instance.createBurstDir(_sessionId);

      // Subscribe before shutter so native pre-roll events are not dropped.
      final surroundingInbox = StreamController<BurstFrameInfo>();
      final surroundingSub = yoloController.listenSurroundingFrames().listen(
        surroundingInbox.add,
        onError: surroundingInbox.addError,
        onDone: () {
          if (!surroundingInbox.isClosed) surroundingInbox.close();
        },
      );
      final surroundingEpoch = yoloController.surroundingListenEpoch;
      unawaited(_drainSurrounding(
        surroundingInbox.stream,
        angleId: seg,
        epoch: surroundingEpoch,
      ).whenComplete(() {
        surroundingSub.cancel();
        if (!surroundingInbox.isClosed) surroundingInbox.close();
      }));

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
        latitude: latitude,
        longitude: longitude,
      );

      return anchor.filePath;
    } catch (_) {
      return null;
    } finally {
      await _awaitCaptureFreeze();
      _isCapturing = false;
      if (!_stopped) notifyListeners();
    }
  }

  static const _burstPostRollCount = 10;

  /// Streams pre-roll + post-roll frames into the upload queue without blocking
  /// freeze / [_isCapturing]. Stops after [_burstPostRollCount] post-roll
  /// frames, or when a newer burst listen starts, or the native stream closes.
  Future<void> _drainSurrounding(
    Stream<BurstFrameInfo> stream, {
    required int angleId,
    required int epoch,
  }) async {
    try {
      var postCount = 0;
      await for (final frame in stream) {
        if (epoch != yoloController.surroundingListenEpoch) break;
        if (frame.isCallEngine) continue;
        await PhotoUploadQueue.instance.enqueuePhoto(
          sessionId: _sessionId,
          angleId: angleId,
          photoIndex: frame.stepIndex,
          filePath: frame.filePath,
          imageOrder: frame.stepIndex,
          isCallEngine: false,
        );
        if (frame.isPostRoll) {
          postCount++;
          if (postCount >= _burstPostRollCount) break;
        }
      }
    } catch (error, stackTrace) {
      debugPrint('AICycle burst surrounding enqueue failed: $error\n$stackTrace');
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
