import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;

import '../../../../core/cache/photo_session_cache.dart';
import '../../../../core/constants/string_sheet.dart';
import '../../../../core/upload/photo_upload_queue.dart';
import '../../../../core/upload/upload_health.dart';
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

  static const _kickInterval = Duration(seconds: 10);

  final _waitPolicy = UploadWaitAlertPolicy();
  List<String> _allPaths = const [];
  UploadAlert? _alert;
  bool _isRetrying = false;

  /// This controller paused the queue for the error screen.
  bool _pausedUploads = false;

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

  /// Set when uploads are failing and the error screen is shown.
  UploadAlert? get alert => _alert;

  /// A request failed and is being retried ("Kết nối chậm, đang thử lại…").
  bool get isRetrying => _isRetrying;

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
    _allPaths = allPaths;
    final initialPending = _pendingCount();

    _uploadedCount = _totalCount - initialPending;
    _status =
        initialPending == 0 ? ResultStatus.success : ResultStatus.uploading;
    _errorMessage = null;
    _alert = null;
    _isRetrying = false;
    _notify();

    final queue = PhotoUploadQueue.instance;
    try {
      // The user is now waiting: short timeouts, quick retries, and photos
      // that failed while capturing are retried right away.
      await queue.setMode(UploadMode.fast);
      await queue.enqueueExistingPhotos(sessionId, snapshot);
      await queue.resumeUploads();
      await queue.drainUploadedResponses(onImageUploaded);
      _waitPolicy.reset();

      var firstCheck = true;
      var lastKick = DateTime.now();
      while (!_disposed) {
        final pending = _pendingCount();
        _uploadedCount = _totalCount - pending;
        if (pending == 0) break;

        final health = await queue.healthForSession(sessionId);
        if (_disposed) return;
        final online = await NetworkStatus.instance.refresh();
        // Discarded meanwhile: must not pause the queue after cancelSession.
        if (_disposed) return;
        final alert = _waitPolicy.evaluate(
          online: online,
          pending: pending,
          health: health,
          reportOfflineImmediately: firstCheck,
        );
        firstCheck = false;

        // Once shown, the error screen stays and uploads stay paused until
        // the user taps "Thử lại" or "Huỷ", even if the network comes back.
        if (_alert == null && alert != null) {
          _alert = alert;
          _errorMessage = _messageFor(alert);
          _status = ResultStatus.error;
          onError?.call(_errorMessage!);
          _pausedUploads = true;
          await queue.pauseUploads();
        }
        _isRetrying = _alert == null && health.streak != null;
        _notify();

        await Future<void>.delayed(const Duration(milliseconds: 500));
        // Native normally drives itself; this periodic kick covers a worker
        // that was stopped by the OS (e.g. Android's 10-minute limit).
        if (DateTime.now().difference(lastKick) >= _kickInterval) {
          lastKick = DateTime.now();
          await queue.resumePendingUploads();
        }
        await queue.drainUploadedResponses(onImageUploaded);
      }
      if (_disposed) return;
      await queue.drainUploadedResponses(onImageUploaded);
      await queue.setMode(UploadMode.background);
      _alert = null;
      _isRetrying = false;

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

  /// "Thử lại" on the error screen. While [start] is still polling (upload
  /// errors) it only resets the backoff; otherwise it restarts [start].
  Future<void> retry() async {
    if (_alert != null && !_disposed) return _retryUploads();
    return start();
  }

  Future<void> _retryUploads() async {
    _alert = null;
    _errorMessage = null;
    _status = ResultStatus.uploading;
    _waitPolicy.reset();
    _notify();
    _pausedUploads = false;
    await PhotoUploadQueue.instance.resumeUploads();
  }

  /// "Huỷ" confirmed: stop every upload and delete the session's photos.
  Future<void> discardSession() async {
    _disposed = true;
    // cancelSession lifts the pause itself.
    _pausedUploads = false;
    final queue = PhotoUploadQueue.instance;
    await queue.cancelSession(sessionId);
    await queue.setMode(UploadMode.background);
    await PhotoSessionCache.instance.clearSession(sessionId);
  }

  /// Captured photos still on disk, i.e. not yet accepted or rejected.
  int get pendingCount => _pendingCount();

  int _pendingCount() =>
      _allPaths.where((path) => File(path).existsSync()).length;

  String _messageFor(UploadAlert alert) => switch (alert) {
        UploadAlert.offline => StringSheet.uploadOffline,
        UploadAlert.server => StringSheet.uploadServerError,
        UploadAlert.stalled => StringSheet.uploadStalled,
      };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// App went to background / came back while the user waits on uploads.
  /// iOS foreground-session uploads cannot run in background, so fall back to
  /// the background session meanwhile.
  Future<void> onAppLifecycleChanged(AppLifecycleState state) async {
    if (_disposed || _status == ResultStatus.success) return;
    final queue = PhotoUploadQueue.instance;
    if (state == AppLifecycleState.paused) {
      await queue.setMode(UploadMode.background);
      await queue.resumePendingUploads();
    } else if (state == AppLifecycleState.resumed) {
      await queue.setMode(UploadMode.fast);
      await queue.retryFailedNow();
      _waitPolicy.reset();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final queue = PhotoUploadQueue.instance;
    unawaited(queue.setMode(UploadMode.background));
    // Left without "Thử lại"/"Huỷ": photos keep uploading in the background.
    if (_pausedUploads) unawaited(queue.resumeUploads());
    super.dispose();
  }
}
