import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/cache/photo_session_cache.dart';
import '../../../../core/utils/gallery_helper.dart';
import '../../domain/repository/result_repository.dart';

enum ResultStatus { uploading, fetchingResult, success, error }

class ResultController extends ChangeNotifier {
  ResultController({
    required this.sessionId,
    required this.capturedPhotos,
    required ResultRepository repository,
    this.onAngleUploaded,
  }) : _repository = repository;

  final String sessionId;

  /// Live reference from CameraController — we snapshot it at [start] time.
  final Map<int, List<Uint8List>> capturedPhotos;
  final ResultRepository _repository;

  /// Called after every angle's photos are fully uploaded so the camera
  /// controller can drop them; prevents re-uploading on a second "next" press.
  final void Function(int angleId)? onAngleUploaded;

  ResultStatus _status = ResultStatus.uploading;
  int _uploadedCount = 0;
  int _totalCount = 0;
  dynamic _result;
  String? _errorMessage;
  bool _disposed = false;

  ResultStatus get status => _status;
  int get uploadedCount => _uploadedCount;
  int get totalCount => _totalCount;
  dynamic get result => _result;
  String? get errorMessage => _errorMessage;

  double get uploadProgress =>
      _totalCount == 0 ? 0 : _uploadedCount / _totalCount;

  Future<void> start() async {
    // Snapshot at call time — camera may add photos while we upload.
    final snapshot = {
      for (final e in capturedPhotos.entries)
        e.key: List<Uint8List>.unmodifiable(e.value),
    };

    _totalCount = snapshot.values.fold(0, (sum, list) => sum + list.length);
    _uploadedCount = 0;
    _status = ResultStatus.uploading;
    _errorMessage = null;
    _notify();

    // Xin quyền thư viện ảnh sớm để khi lưu ảnh upload thành công không bị
    // block bởi dialog xin quyền (no-op nếu savePhotoAfterShot = false).
    await GalleryHelper.requestPermission();

    try {
      for (final entry in snapshot.entries) {
        final angleId = entry.key;
        final photos = entry.value;

        for (int i = 0; i < photos.length; i++) {
          await _repository.uploadAnglePhoto(
            angleId: angleId,
            photoBytes: photos[i],
            photoIndex: i,
          );
          // Upload thành công → lưu ảnh vào thư viện ảnh của thiết bị.
          unawaited(GalleryHelper.saveBytes(photos[i]));
          _uploadedCount++;
          _notify();
        }

        // Clear disk cache then notify camera to drop in-memory copy.
        await PhotoSessionCache.instance.clearAngle(sessionId, angleId);
        onAngleUploaded?.call(angleId);
      }

      _status = ResultStatus.fetchingResult;
      _notify();

      _result = await _repository.fetchResult();
      _status = ResultStatus.success;
      _notify();
    } catch (e) {
      _errorMessage = e.toString();
      _status = ResultStatus.error;
      _notify();
    }
  }

  Future<void> retry() => start();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
