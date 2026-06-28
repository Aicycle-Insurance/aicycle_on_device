import 'dart:async';
import 'dart:nativewrappers/_internal/vm/lib/ffi_allocation_patch.dart';

import 'package:flutter/foundation.dart';

import '../../../../core/cache/photo_session_cache.dart';
import '../../../../core/utils/gallery_helper.dart';
import '../../domain/entity/inspection_result.dart';
import '../../domain/repository/result_repository.dart';

enum ResultStatus { uploading, fetchingResult, success, error }

class ResultController extends ChangeNotifier {
  ResultController({
    required this.sessionId,
    required this.capturedPhotos,
    required ResultRepository repository,
    this.onAngleUploaded,
    this.onImageUploaded,
    this.onError,
    this.fetchResultAfterUpload = true,
  }) : _repository = repository;

  final String sessionId;

  /// Live reference from CameraController — we snapshot it at [start] time.
  final Map<int, List<Uint8List>> capturedPhotos;
  final ResultRepository _repository;

  /// Khi `false` chỉ upload ảnh rồi dừng (không gọi API lấy kết quả) — dùng cho
  /// flow camera đã bỏ màn ResultView, chỉ cần upload xong là [start] hoàn tất.
  final bool fetchResultAfterUpload;

  /// Called after every angle's photos are fully uploaded so the camera
  /// controller can drop them; prevents re-uploading on a second "next" press.
  final void Function(int angleId)? onAngleUploaded;

  /// Gọi mỗi khi MỘT ảnh upload thành công, kèm body JSON server trả về cho
  /// ảnh đó.
  final void Function(Map<String, dynamic> data)? onImageUploaded;

  final void Function(String)? onError;

  ResultStatus _status = ResultStatus.uploading;
  int _uploadedCount = 0;
  int _totalCount = 0;
  List<VehiclePart>? _result;
  String? _errorMessage;
  bool _disposed = false;

  ResultStatus get status => _status;
  int get uploadedCount => _uploadedCount;
  int get totalCount => _totalCount;
  List<VehiclePart>? get result => _result;
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

    // Không có ảnh nào để upload (vd folder đã có sẵn kết quả) → lấy kết quả
    // luôn, bỏ qua upload + xin quyền + lưu gallery.
    if (_totalCount == 0) {
      if (fetchResultAfterUpload) {
        await _fetchResultOnly();
      } else {
        _status = ResultStatus.success;
        _notify();
      }
      return;
    }

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
          try {
            final data = await _repository.uploadAnglePhoto(
              angleId: angleId,
              photoBytes: photos[i],
              photoIndex: i,
            );
            // Upload thành công → trả data về host (nếu server có phản hồi JSON).
            if (data != null) onImageUploaded?.call(data);
            // Upload thành công → lưu ảnh vào thư viện ảnh của thiết bị.
            unawaited(GalleryHelper.saveBytes(photos[i]));
          } catch (e) {
            // Ảnh này upload fail → call back error, không chặn flow.
            onError?.call(e.toString());
          }
          // Đếm cả ảnh fail để tiến độ chạy tới 100% và flow tiếp tục.
          _uploadedCount++;
          _notify();
        }

        // Clear disk cache then notify camera to drop in-memory copy.
        await PhotoSessionCache.instance.clearAngle(sessionId, angleId);
        onAngleUploaded?.call(angleId);
      }

      // Bỏ màn kết quả khỏi flow → chỉ upload xong là dừng.
      if (fetchResultAfterUpload) {
        _status = ResultStatus.fetchingResult;
        _notify();
        _result = await _repository.fetchResult();
      }
      _status = ResultStatus.success;
      _notify();
    } catch (e) {
      _errorMessage = e.toString();
      _status = ResultStatus.error;
      _notify();
    }
  }

  /// Lấy kết quả luôn, không qua bước upload (dùng khi folder đã có kết quả).
  Future<void> _fetchResultOnly() async {
    _status = ResultStatus.fetchingResult;
    _errorMessage = null;
    _notify();
    try {
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
