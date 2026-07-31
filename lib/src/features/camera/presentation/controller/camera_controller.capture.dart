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

  /// Captures a JPEG frame, writes it to disk and enqueues it for background
  /// upload.
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
      // Paint the white shutter-blink NGAY trước khi gọi native capture (có thể
      // chiếm thời gian) để blink hiện đồng bộ với khoảnh khắc chụp, thay vì chỉ
      // hiện sau khi capture xong.
      if (flashTick) _captureFlashTick++;
      // Khung góc nháy success ở MỌI lần chụp — kể cả chụp ngầm không blink —
      // cùng thời điểm với blink (tự notify). Giữ đúng bằng hiệu ứng dừng hình:
      // ảnh đóng băng che khung góc, nên khung xanh phải còn sống khi ảnh co về
      // thumbnail và để lộ khung ra lại.
      _flashCornerSuccess(_captureFreezeDuration);

      final seg = segment ?? _activeSegmentIndex;
      if (seg != null) {
        final photoIndex = _capturedPhotos[seg]?.length ?? 0;
        final path = await PhotoSessionCache.instance.createPhotoPath(
          _sessionId,
          seg,
        );
        await yoloController.capturePhotoToFile(
          filePath: path,
          thumbnailPath: PhotoSessionCache.thumbnailPathForPhotoPath(path),
          cropTop: _cropTop,
          cropBottom: _cropBottom,
          quality: 80,
        );
        _capturedPhotos.putIfAbsent(seg, () => []).add(path);
        // Persist the queue entry and hand it to WorkManager/background
        // URLSession before reporting capture completion. This closes the small
        // window where a user could terminate the app immediately after the
        // shutter and leave the photo on disk but not scheduled.
        await PhotoUploadQueue.instance.enqueuePhoto(
          sessionId: _sessionId,
          angleId: seg,
          photoIndex: photoIndex,
          filePath: path,
        );
        // Config 4 góc TẮT: góc nào đã có ảnh là hiện màu xanh trên vòng tròn.
        if (!_require4Angles) _completedSegments.add(seg);
        notifyListeners();
        // Dừng hình ảnh vừa chụp rồi co về thumbnail — áp dụng cho MỌI lần chụp
        // (mọi lần khung góc nháy xanh success), kể cả chụp ngầm không blink.
        // Chờ hết hiệu ứng trước khi trả về để message/pha kế tiếp không cắt
        // ngang: đây là nhịp để user kịp nhận ra ảnh đã được chụp.
        await _playCaptureFreeze(path);
        return path;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      _isCapturing = false;
      // Nhịp chờ (delay auto-capture / hiệu ứng dừng hình) có thể kéo dài qua
      // lúc user đóng màn camera → controller đã dispose, không notify nữa.
      if (!_stopped) notifyListeners();
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
