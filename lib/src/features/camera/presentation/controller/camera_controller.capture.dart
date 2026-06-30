part of 'camera_controller.dart';

/// Chụp & lưu ảnh (in-memory + disk cache) và khôi phục ảnh từ cache.
mixin _CaptureMixin on _CameraControllerBase {
  // ── Cache restore ─────────────────────────────────────────────────────────

  /// Restores previously captured photos from disk cache.
  /// Call once after construction; notifies listeners when done.
  Future<void> loadCachedPhotos() async {
    final cached = await PhotoSessionCache.instance.loadSession(_sessionId);
    if (cached.isEmpty) return;
    _capturedPhotos = cached;
    // Angles with cached photos are shown as completed in the progress ring.
    _completedSegments.addAll(cached.keys);
    notifyListeners();
  }

  // ── Photo capture ─────────────────────────────────────────────────────────

  /// Captures a JPEG frame, stores it in memory and on disk.
  /// Does NOT modify [_completedSegments] — completion is via
  /// [_InspectionMixin.completeCurrentAngle].
  @override
  Future<Uint8List?> capturePhoto({
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
      if (flashTick) {
        _captureFlashTick++;
        // Paint the white shutter-blink NGAY trước khi gọi native capture (có thể
        // chiếm thời gian) để blink hiện đồng bộ với khoảnh khắc chụp, thay vì chỉ
        // hiện sau khi capture xong.
        notifyListeners();
      }

      final bytes = await yoloController.capturePhoto(
        cropTop: _cropTop,
        cropBottom: _cropBottom,
      );
      final seg = segment ?? _activeSegmentIndex;
      if (seg != null) {
        _capturedPhotos.putIfAbsent(seg, () => []).add(bytes);
        PhotoSessionCache.instance.savePhoto(_sessionId, seg, bytes);
        // Config 4 góc TẮT: góc nào đã có ảnh là hiện màu xanh trên vòng tròn
        // góc (không cần qua bước "Chuyển góc" như flow 4 góc).
        if (!_require4Angles) _completedSegments.add(seg);
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

  /// Chụp thủ công bằng nút shutter: chụp ngay, lưu vào góc đang active (mặc
  /// định góc 0 nếu chưa phân loại được góc).
  Future<void> manualCapture() =>
      capturePhoto(immediate: true, segment: _activeSegmentIndex ?? 0);

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
