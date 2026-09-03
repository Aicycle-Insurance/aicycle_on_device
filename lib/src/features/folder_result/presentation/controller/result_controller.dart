import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../core/upload/photo_upload_queue.dart';
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
  final Map<int, List<String>> capturedPhotos;
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
        e.key: List<String>.unmodifiable(e.value),
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

    final allPaths = snapshot.values.expand((paths) => paths).toList();
    final initialPending =
        allPaths.where((path) => File(path).existsSync()).length;

    _uploadedCount = _totalCount - initialPending;
    _status =
        initialPending == 0 ? ResultStatus.success : ResultStatus.uploading;
    _errorMessage = null;
    _notify();

    try {
      await PhotoUploadQueue.instance.enqueueExistingPhotos(
        sessionId,
        snapshot,
      );
      await PhotoUploadQueue.instance.resumePendingUploads();
      await PhotoUploadQueue.instance.drainUploadedResponses(onImageUploaded);

      while (!_disposed) {
        final pending =
            allPaths.where((path) => File(path).existsSync()).length;
        _uploadedCount = _totalCount - pending;
        _notify();
        if (pending == 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
        await PhotoUploadQueue.instance.resumePendingUploads();
        await PhotoUploadQueue.instance.drainUploadedResponses(onImageUploaded);
      }
      if (_disposed) return;
      await PhotoUploadQueue.instance.drainUploadedResponses(onImageUploaded);

      for (final angleId in snapshot.keys) {
        onAngleUploaded?.call(angleId);
      }

      // Bỏ màn kết quả khỏi flow → chỉ upload xong là dừng khi fetchResultAfterUpload == false.
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
