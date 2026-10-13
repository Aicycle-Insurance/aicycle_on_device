import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../config/aicycle_config.dart';
import '../../config/aicycle_config_internal.dart';
import '../../config/config_holder.dart';
import '../cache/photo_session_cache.dart';

class PhotoUploadQueue {
  PhotoUploadQueue._();
  static final PhotoUploadQueue instance = PhotoUploadQueue._();

  static const _metadataFileName = 'upload_queue.json';
  static const _channel = MethodChannel('yolo_single_image_channel');
  static const maxCacheBytes = 500 * 1024 * 1024;
  static const maxCachePhotos = 300;

  /// `errorCodeFromEngine` values that make an HTTP 400 retryable like a 5xx.
  /// The server has stored the photo but its AI engine failed transiently
  /// (10012 = engine request timeout); the server de-duplicates the retry by
  /// captureSessionId + imageOrder. Native reads this list from the queue file.
  static const retryableEngineErrorCodes = [10012];

  final Map<Object, _UploadResponseListener> _responseListeners = {};
  Timer? _responseDeliveryTimer;
  bool _isDrainingResponses = false;
  Future<void> _mutationTail = Future<void>.value();
  int _tempFileSequence = 0;
  UploadMode _mode = UploadMode.background;

  /// Kept in memory on purpose: a fresh process starts unpaused and its first
  /// queue write clears a `paused` flag left by a killed app.
  bool _paused = false;

  UploadMode get mode => _mode;
  bool get isPaused => _paused;

  Object? addUploadedResponseListener(
    void Function(Map<String, dynamic> data)? listener, {
    String? sessionId,
    bool keepAliveAfterRemove = false,
  }) {
    if (listener == null) return null;
    final token = Object();
    _responseListeners[token] = _UploadResponseListener(
      sessionId: sessionId,
      onData: listener,
      keepAliveAfterRemove: keepAliveAfterRemove,
    );
    _ensureResponseDeliveryTimer();
    unawaited(_drainResponsesToActiveListener());
    return token;
  }

  void removeUploadedResponseListener(Object? token) {
    if (token == null) return;
    final listener = _responseListeners[token];
    if (listener == null) return;
    if (listener.keepAliveAfterRemove) {
      listener.detachedAt ??= DateTime.now();
      _ensureResponseDeliveryTimer();
      unawaited(_drainResponsesToActiveListener());
      return;
    }
    _responseListeners.remove(token);
    if (_responseListeners.isEmpty) {
      _responseDeliveryTimer?.cancel();
      _responseDeliveryTimer = null;
    }
  }

  void _ensureResponseDeliveryTimer() {
    if (_responseDeliveryTimer != null) return;
    _responseDeliveryTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_drainResponsesToActiveListener()),
    );
  }

  Future<void> _drainResponsesToActiveListener() async {
    if (_responseListeners.isEmpty) return;
    if (_isDrainingResponses) return;
    _isDrainingResponses = true;
    try {
      final items = await _readItems();
      _removeExpiredDetachedListeners();

      final deliveredIds = <String>{};
      for (final item in items) {
        if (!item.hasPendingResponse) continue;
        final listener = _lastMatchingListener(item.sessionId);
        final data = _decodeResponseMap(item);

        if (item.isCallEngine) {
          if (listener == null) continue;
          debugPrint(
            'AICycle upload completed: session=${item.sessionId} '
            'angle=${item.angleId} photo=${item.photoIndex} '
            'status=${item.responseStatusCode}',
          );
          try {
            listener.onData(data);
          } catch (_) {
            // Host callback errors must not block queue cleanup or replay.
          }
        } else {
          debugPrint(
            'AICycle context stream ok: imageOrder=${item.imageOrder} '
            'httpCode=${item.responseStatusCode}',
          );
        }
        _deleteStreamFileIfNeeded(item);
        deliveredIds.add(item.id);
      }

      final nextItems = deliveredIds.isEmpty
          ? items
          : await _mutateItems((latestItems) => [
                for (final item in latestItems)
                  if (!deliveredIds.contains(item.id)) item,
              ]);
      _removeIdleDetachedListeners(nextItems);
      _stopResponseTimerIfIdle();
    } catch (error, stackTrace) {
      // This method is also started from a periodic timer via unawaited. Keep a
      // transient filesystem race from becoming an unhandled app exception;
      // the response stays in the queue and is retried on the next tick.
      debugPrint(
        'AICycle upload response delivery deferred: $error\n$stackTrace',
      );
    } finally {
      _isDrainingResponses = false;
    }
  }

  Future<void> drainUploadedResponses(
    void Function(Map<String, dynamic> data)? onImageUploaded,
  ) async {
    if (onImageUploaded == null || _isDrainingResponses) return;
    _isDrainingResponses = true;
    try {
      final items = await _readItems();
      final deliveredIds = <String>{};

      for (final item in items) {
        if (!item.hasPendingResponse) continue;
        final data = _decodeResponseMap(item);
        if (item.isCallEngine) {
          debugPrint(
            'AICycle upload completed: session=${item.sessionId} '
            'angle=${item.angleId} photo=${item.photoIndex} '
            'status=${item.responseStatusCode}',
          );
          try {
            onImageUploaded(data);
          } catch (_) {
            // Host callback errors must not block queue cleanup or replay.
          }
        } else {
          debugPrint(
            'AICycle context stream ok: imageOrder=${item.imageOrder} '
            'httpCode=${item.responseStatusCode}',
          );
        }
        _deleteStreamFileIfNeeded(item);
        deliveredIds.add(item.id);
      }

      if (deliveredIds.isEmpty) return;
      await _mutateItems((latestItems) => [
            for (final item in latestItems)
              if (!deliveredIds.contains(item.id)) item,
          ]);
    } finally {
      _isDrainingResponses = false;
    }
  }

  _UploadResponseListener? _lastMatchingListener(String sessionId) {
    _UploadResponseListener? found;
    for (final listener in _responseListeners.values) {
      if (listener.matches(sessionId)) found = listener;
    }
    return found;
  }

  void _removeExpiredDetachedListeners() {
    final now = DateTime.now();
    _responseListeners.removeWhere((_, listener) {
      final detachedAt = listener.detachedAt;
      return detachedAt != null &&
          now.difference(detachedAt) >=
              _UploadResponseListener.detachedKeepAlive;
    });
  }

  void _removeIdleDetachedListeners(List<PhotoUploadItem> items) {
    _responseListeners.removeWhere((_, listener) {
      if (listener.detachedAt == null) return false;
      return !items.any(listener.hasWorkFor);
    });
  }

  void _stopResponseTimerIfIdle() {
    if (_responseListeners.isNotEmpty) return;
    _responseDeliveryTimer?.cancel();
    _responseDeliveryTimer = null;
  }

  Future<void> enqueuePhoto({
    required String sessionId,
    required int angleId,
    required int photoIndex,
    required String filePath,
    int? imageOrder,
    String? captureSessionId,
    bool isCallEngine = false,
    double? latitude,
    double? longitude,
  }) =>
      _enqueuePhoto(
        sessionId: sessionId,
        angleId: angleId,
        photoIndex: photoIndex,
        filePath: filePath,
        imageOrder: imageOrder,
        captureSessionId: captureSessionId,
        isCallEngine: isCallEngine,
        latitude: latitude,
        longitude: longitude,
        schedule: true,
      );

  Future<void> _enqueuePhoto({
    required String sessionId,
    required int angleId,
    required int photoIndex,
    required String filePath,
    int? imageOrder,
    String? captureSessionId,
    bool isCallEngine = false,
    double? latitude,
    double? longitude,
    required bool schedule,
    bool keepExisting = false,
  }) async {
    final request = _buildUploadRequest(isCallEngine: isCallEngine);
    final fields = {
      ...request.fields,
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
      if (imageOrder != null) 'imageOrder': imageOrder.toString(),
      if (captureSessionId != null) 'captureSessionId': captureSessionId,
      'isCallEngine': isCallEngine ? 'true' : 'false',
    };
    final fileName = isCallEngine
        ? '${angleId}_$photoIndex.jpg'
        : 'stream_${angleId}_$photoIndex.jpg';
    final item = PhotoUploadItem(
      id: _stableId('$sessionId|$angleId|$filePath'),
      sessionId: sessionId,
      angleId: angleId,
      photoIndex: photoIndex,
      imageOrder: imageOrder,
      captureSessionId: captureSessionId,
      isCallEngine: isCallEngine,
      filePath: filePath,
      fileName: fileName,
      fileField: request.fileField,
      url: request.url,
      headers: request.headers,
      fields: fields,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    var alreadyQueued = false;
    await _mutateItems((items) {
      if (keepExisting &&
          items.any((existing) =>
              existing.id == item.id ||
              (existing.sessionId == item.sessionId &&
                  existing.filePath == item.filePath))) {
        alreadyQueued = true;
        return items;
      }
      return [
        for (final existing in items)
          if (existing.id != item.id) existing,
        item,
      ];
    });
    if (alreadyQueued) return;
    debugPrint(
      'AICycle upload queued: session=$sessionId angle=$angleId '
      'photo=$photoIndex imageOrder=$imageOrder '
      'captureSessionId=$captureSessionId isCallEngine=$isCallEngine '
      'file=${item.fileName}',
    );
    await enforceCacheLimit();
    // Only the new photo: rescanning the whole queue on every capture (and
    // every context-stream frame) floods the platform channel when uploads
    // are backed up.
    if (schedule) await _bestEffortSchedule(() => _scheduleItems([item]));
  }

  /// Re-queues photos still on disk (app resume, "Kết thúc chụp ảnh").
  ///
  /// Photos already in the queue are left untouched: their captureSessionId,
  /// imageOrder and retry state must stay exactly as captured, otherwise a
  /// retry no longer matches the first attempt and the server cannot
  /// de-duplicate it. Only photos missing from the queue (e.g. the app was
  /// killed right after the shutter) are added.
  Future<void> enqueueExistingPhotos(
    String sessionId,
    Map<int, List<String>> photoPaths, {
    String? captureSessionId,
  }) async {
    final allPhotos = <_ExistingPhotoInfo>[];
    for (final entry in photoPaths.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final path = entry.value[i];
        if (File(path).existsSync()) {
          allPhotos.add(_ExistingPhotoInfo(
            angleId: entry.key,
            photoIndex: i,
            path: path,
          ));
        }
      }
    }
    allPhotos.sort((a, b) => a.path.compareTo(b.path));

    for (var idx = 0; idx < allPhotos.length; idx++) {
      final photo = allPhotos[idx];
      await _enqueuePhoto(
        sessionId: sessionId,
        angleId: photo.angleId,
        photoIndex: photo.photoIndex,
        filePath: photo.path,
        imageOrder: idx + 1,
        captureSessionId: captureSessionId,
        isCallEngine: true,
        schedule: false,
        keepExisting: true,
      );
    }
    await _schedulePendingUploadsBestEffort();
  }

  Future<void> resumePendingUploads() async {
    await _removeMissingOrSucceededItems();
    await _schedulePendingUploadsBestEffort();
    await _drainResponsesToActiveListener();
  }

  Future<void> resumeSession(String sessionId) async {
    final cached = await PhotoSessionCache.instance.loadSessionPhotoPaths(
      sessionId,
    );
    if (cached.isNotEmpty) {
      await enqueueExistingPhotos(sessionId, cached);
    }
    await resumePendingUploads();
  }

  Future<void> clearSession(String sessionId) async {
    await _mutateItems((items) => [
          for (final item in items)
            if (item.sessionId != sessionId) item,
        ]);
  }

  Future<UploadQueueProgress> progressForSession(String sessionId) async {
    await _removeMissingOrSucceededItems();
    final items = (await _readItems())
        .where((item) => item.sessionId == sessionId)
        .toList();
    final total = items.length;
    final pending =
        items.where((item) => File(item.filePath).existsSync()).length;
    return UploadQueueProgress(
      total: total,
      uploaded: total - pending,
      pending: pending,
    );
  }

  Future<void> enforceCacheLimit() async {
    final root = await PhotoSessionCache.instance.rootDir();
    if (!root.existsSync()) return;

    final files = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.jpg'))
        .toList();
    if (files.isEmpty) return;

    final stats = [
      for (final file in files)
        _PhotoFileStat(file: file, stat: file.statSync()),
    ]..sort((a, b) => a.stat.modified.compareTo(b.stat.modified));

    var totalBytes = stats.fold<int>(0, (sum, e) => sum + e.stat.size);
    var totalPhotos = stats.length;
    for (final entry in stats) {
      if (totalBytes <= maxCacheBytes && totalPhotos <= maxCachePhotos) break;
      try {
        entry.file.deleteSync();
      } catch (_) {
        // Best effort cleanup; a native background task may currently own it.
      }
      totalBytes -= entry.stat.size;
      totalPhotos--;
    }
    await _removeMissingOrSucceededItems();
  }

  Future<File> _metadataFile({bool create = false}) async {
    final root = await PhotoSessionCache.instance.rootDir(create: create);
    final file = File('${root.path}/$_metadataFileName');
    if (create && !file.existsSync()) {
      await file.writeAsString(jsonEncode({'version': 1, 'items': []}));
    }
    return file;
  }

  Future<List<PhotoUploadItem>> _readItems() async =>
      (await _readQueue()).items;

  /// Reads the whole queue document: items plus the top-level bookkeeping the
  /// native uploaders write (`failureStreak`, `lastSuccessAtMillis`).
  Future<_QueueDocument> _readQueue() async {
    final file = await _metadataFile();
    if (!file.existsSync()) return _QueueDocument.empty();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return _QueueDocument.empty();
      final meta = Map<String, dynamic>.from(decoded)..remove('items');
      final rawItems = decoded['items'];
      final items = rawItems is! List
          ? <PhotoUploadItem>[]
          : rawItems
              .whereType<Map>()
              .map(
                  (e) => PhotoUploadItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
      return _QueueDocument(meta: meta, items: items);
    } catch (_) {
      return _QueueDocument.empty();
    }
  }

  Future<void> _writeQueue(_QueueDocument queue) async {
    final file = await _metadataFile(create: true);
    final tmp = File(
      '${file.path}.dart-$pid-${DateTime.now().microsecondsSinceEpoch}-'
      '${_tempFileSequence++}.tmp',
    );
    try {
      await tmp.writeAsString(
        jsonEncode({
          ...queue.meta,
          'version': 1,
          'mode': _mode.name,
          'paused': _paused,
          'retryableEngineErrorCodes': retryableEngineErrorCodes,
          'items': [for (final item in queue.items) item.toJson()],
        }),
        flush: true,
      );
      // rename replaces the destination atomically on Android/iOS. Keeping a
      // unique temp path prevents Dart and the native background worker from
      // moving/deleting each other's temp file.
      await tmp.rename(file.path);
    } finally {
      if (tmp.existsSync()) {
        try {
          await tmp.delete();
        } catch (_) {
          // Best-effort cleanup; the rename may already have consumed it.
        }
      }
    }
  }

  Future<T> _withMutationLock<T>(Future<T> Function() action) async {
    final previous = _mutationTail;
    final release = Completer<void>();
    _mutationTail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      release.complete();
    }
  }

  Future<List<PhotoUploadItem>> _mutateItems(
    List<PhotoUploadItem> Function(List<PhotoUploadItem> items) mutate,
  ) =>
      _mutateQueue((meta, items) => mutate(items));

  /// Like [_mutateItems] but [mutate] may also edit the top-level [meta].
  Future<List<PhotoUploadItem>> _mutateQueue(
    List<PhotoUploadItem> Function(
      Map<String, dynamic> meta,
      List<PhotoUploadItem> items,
    ) mutate,
  ) =>
      _withMutationLock(() async {
        final latest = await _readQueue();
        final meta = Map<String, dynamic>.from(latest.meta);
        final nextItems = mutate(meta, latest.items);
        await _writeQueue(_QueueDocument(meta: meta, items: nextItems));
        return nextItems;
      });

  Future<void> _removeMissingOrSucceededItems() async {
    await _mutateItems((items) => [
          for (final item in items)
            if (item.hasPendingResponse ||
                (!item.status.isTerminal && File(item.filePath).existsSync()))
              item,
        ]);
  }

  /// Full rescan: schedules every due item (app resume, "Thử lại", periodic
  /// kick). A new capture only schedules itself, see [_enqueuePhoto].
  Future<void> schedulePendingUploads() async {
    if (_paused) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final items = (await _readItems())
        .where(
          (item) =>
              !item.status.isTerminal &&
              item.nextAttemptAtMillis <= now &&
              File(item.filePath).existsSync(),
        )
        .toList();
    await _scheduleItems(items);
  }

  /// Hands [items] to native. Android drains the whole queue file in one
  /// worker, so a single call covers any number of items. iOS de-duplicates
  /// items that already have an active task.
  Future<void> _scheduleItems(List<PhotoUploadItem> items) async {
    if (_paused || items.isEmpty) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final file = await _metadataFile(create: true);

    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('schedulePhotoUploadQueue', {
        'queueFilePath': file.path,
      });
      return;
    }

    for (final item in items) {
      await _channel.invokeMethod<void>(
        'schedulePhotoUpload',
        {...item.toPlatformMap(queueFilePath: file.path), 'mode': _mode.name},
      );
    }
    if (items.length > 1) {
      debugPrint('AICycle upload scheduled on iOS: ${items.length} items');
    }
  }

  Future<void> _schedulePendingUploadsBestEffort() =>
      _bestEffortSchedule(schedulePendingUploads);

  Future<void> _bestEffortSchedule(Future<void> Function() schedule) async {
    try {
      await schedule();
    } on PlatformException catch (error) {
      // The queue item is already durable on disk. A lifecycle resume or the
      // next capture will schedule it again, so a transient platform-channel
      // failure must not turn a successfully captured photo into a failure.
      debugPrint('AICycle upload scheduling deferred: ${error.message}');
    }
  }

  /// Switches the native uploaders between [UploadMode.background] (still
  /// capturing: generous timeouts, long backoff) and [UploadMode.fast] (user
  /// waits on the upload screen: short timeouts, quick retries).
  Future<void> setMode(UploadMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    await _mutateItems((items) => items);
  }

  /// Forgets the current failure streak so warning thresholds count from now.
  Future<void> resetFailureStreak() => _mutateQueue((meta, items) {
        meta.remove(_failureStreakKey);
        return items;
      });

  /// "Thử lại": clears every pending photo's backoff and uploads it right
  /// away. Uploads already sending bytes are left running.
  Future<void> retryFailedNow() async {
    if (_paused) return;
    final file = await _metadataFile(create: true);
    try {
      // iOS drops tasks still waiting on backoff before they are rescheduled
      // below; Android drops its delayed wakeup and drains immediately.
      if (Platform.isIOS) {
        await _channel.invokeMethod<void>('retryPhotoUploadsNow');
      }
    } on PlatformException catch (error) {
      debugPrint('AICycle upload retry-now failed: ${error.message}');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _mutateQueue((meta, items) {
      meta.remove(_failureStreakKey);
      return [
        for (final item in items)
          item.status == PhotoUploadStatus.failed
              ? item.copyForImmediateRetry(now)
              : item,
      ];
    });
    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod<void>('retryPhotoUploadsNow', {
          'queueFilePath': file.path,
        });
        return;
      }
    } on PlatformException catch (error) {
      debugPrint('AICycle upload retry-now failed: ${error.message}');
    }
    await _schedulePendingUploadsBestEffort();
  }

  /// Upload error shown to the user: stops every upload (in-flight included)
  /// and keeps native from retrying on its own until [resumeUploads].
  /// Photos stay queued.
  Future<void> pauseUploads() async {
    if (_paused) return;
    _paused = true;
    // Persist first so native retries that race with the cancel see the flag.
    await _mutateItems((items) => items);
    // Resumed or cancelled meanwhile: do not kill what was just rescheduled.
    if (!_paused) return;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _channel.invokeMethod<void>('cancelPhotoUploads');
      }
    } on PlatformException catch (error) {
      debugPrint('AICycle upload pause failed: ${error.message}');
    }
  }

  /// "Thử lại" / "Chụp tiếp": lifts [pauseUploads] and sends everything left
  /// right away.
  Future<void> resumeUploads() async {
    _paused = false;
    await retryFailedNow();
  }

  /// Cancels native uploads (in-flight included) and drops [sessionId] from
  /// the queue. Photo files are deleted by `PhotoSessionCache.clearSession`.
  /// Also lifts [pauseUploads] so other sessions' photos keep uploading.
  Future<void> cancelSession(String sessionId) async {
    _paused = false;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await _channel.invokeMethod<void>('cancelPhotoUploads');
      }
    } on PlatformException catch (error) {
      debugPrint('AICycle upload cancel failed: ${error.message}');
    }
    final remaining = await _mutateQueue((meta, items) {
      meta.remove(_failureStreakKey);
      return [
        for (final item in items)
          if (item.sessionId != sessionId) item,
      ];
    });
    // Cancelling is global on the native side; resume other sessions' photos.
    if (remaining.any((item) => !item.status.isTerminal)) {
      await _schedulePendingUploadsBestEffort();
    }
  }

  /// Snapshot used by the upload warning logic (see `upload_health.dart`).
  Future<UploadHealthSnapshot> healthForSession(String sessionId) async {
    final queue = await _readQueue();
    final pendingItems = queue.items
        .where((item) =>
            item.sessionId == sessionId &&
            item.isCallEngine &&
            !item.status.isTerminal &&
            File(item.filePath).existsSync())
        .toList();
    final rawStreak = queue.meta[_failureStreakKey];
    return UploadHealthSnapshot(
      pending: pendingItems.length,
      failing: pendingItems
          .where((item) => item.status == PhotoUploadStatus.failed)
          .length,
      streak: rawStreak is Map
          ? UploadFailureStreak.fromJson(Map<String, dynamic>.from(rawStreak))
          : null,
      lastSuccessAtMillis: queue.meta['lastSuccessAtMillis'] as int?,
      lastResponseAtMillis: queue.meta['lastResponseAtMillis'] as int?,
      pendingQueuedAtMillis: [
        for (final item in pendingItems) item.createdAtMillis,
      ],
    );
  }

  _UploadRequest _buildUploadRequest({required bool isCallEngine}) {
    final config = AICycleConfigHolder.config;
    final sessionId = config.generalConfig.documentId;

    if (isCallEngine && config.generalConfig.organization == AiCycleOrg.vbi) {
      final vbi = config.vbiConfig!;
      return _UploadRequest(
        url:
            '${vbi.apiUploadBaseUrl}/api/${vbi.apiVersionCode}/vbi4sales/Upload/upload-ai',
        fileField: 'Image',
        headers: {
          'Authority': vbi.authorityId,
          'Signature': vbi.signatureKey,
          'Accept': 'application/json',
        },
        fields: {
          'ExternalSessionId': vbi.externalSessionId,
          'jobId': vbi.jobId,
          'ma_hang_muc': vbi.maHangMuc,
          'so_id_hs': sessionId,
          'ten_hang_muc': vbi.tenHangMuc,
          'departmentId': vbi.departmentId,
          'user': vbi.userId,
          'ma_tvv': vbi.maTVV,
          'source': vbi.source,
          'btx_khoang_cach': vbi.btxKhoangCach,
          'dia_chi': vbi.diaChi,
          'sdk': vbi.sdk,
        },
      );
    }

    final isAicycle = config.generalConfig.organization == AiCycleOrg.aicycle;
    return _UploadRequest(
      url: '${config.baseUrl}/insurance/v2/claim-me/upload',
      fileField: 'img',
      headers: {
        'Authorization': 'Bearer ${config.generalConfig.apiToken}',
        'x-aicycle-application': isAicycle ? 'appDemo' : 'api',
        'Accept': 'application/json',
      },
      fields: {
        if (isAicycle) 'claimFolderId': sessionId,
        if (!isAicycle) 'externalSessionId': sessionId,
      },
    );
  }

  String _stableId(String input) {
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode(input)) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return hash.toRadixString(16);
  }

  /// Server body for the host callback. `uploaded` tells the host whether the
  /// photo was accepted (2xx) or rejected by the server.
  Map<String, dynamic> _decodeResponseMap(PhotoUploadItem item) {
    final body = item.responseBody?.trim() ?? '';
    if (body.isEmpty) return _fallbackUploadResponse(item);
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded)
          ..putIfAbsent('uploaded', () => item.isAccepted);
      }
    } catch (_) {
      // Non-JSON bodies still carry the HTTP status below.
    }
    return _fallbackUploadResponse(item, rawBody: body);
  }

  Map<String, dynamic> _fallbackUploadResponse(
    PhotoUploadItem item, {
    String? rawBody,
  }) {
    return {
      'uploaded': item.isAccepted,
      'statusCode': item.responseStatusCode,
      'sessionId': item.sessionId,
      'angleId': item.angleId,
      'photoIndex': item.photoIndex,
      'fileName': item.fileName,
      if (rawBody != null && rawBody.isNotEmpty) 'rawBody': rawBody,
    };
  }

  void _deleteStreamFileIfNeeded(PhotoUploadItem item) {
    if (item.isCallEngine) return;
    if (!item.filePath.contains('/_stream/')) return;
    try {
      final file = File(item.filePath);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best-effort cleanup after upload.
    }
  }
}

class PhotoUploadItem {
  PhotoUploadItem({
    required this.id,
    required this.sessionId,
    required this.angleId,
    required this.photoIndex,
    this.imageOrder,
    this.captureSessionId,
    this.isCallEngine = false,
    required this.filePath,
    required this.fileName,
    required this.fileField,
    required this.url,
    required this.headers,
    required this.fields,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    this.status = PhotoUploadStatus.pending,
    this.attempt = 0,
    this.nextAttemptAtMillis = 0,
    this.lastError,
    this.errorType,
    this.lastFailedAtMillis,
    this.lastStatusCode,
    this.responseBody,
    this.responseStatusCode,
  });

  final String id;
  final String sessionId;
  final int angleId;
  final int photoIndex;
  final int? imageOrder;
  final String? captureSessionId;
  final bool isCallEngine;
  final String filePath;
  final String fileName;
  final String fileField;
  final String url;
  final Map<String, String> headers;
  final Map<String, String> fields;
  final PhotoUploadStatus status;
  final int attempt;
  final int nextAttemptAtMillis;
  final int createdAtMillis;
  final int updatedAtMillis;
  final String? lastError;

  /// Category of the last failure, written by native: `network`, `timeout`,
  /// `server` (all retried) or `rejected` (final).
  final String? errorType;
  final int? lastFailedAtMillis;
  final int? lastStatusCode;
  final String? responseBody;
  final int? responseStatusCode;

  /// Final server answer not yet delivered to the host.
  bool get hasPendingResponse =>
      (status == PhotoUploadStatus.succeeded ||
          status == PhotoUploadStatus.rejected) &&
      responseStatusCode != null &&
      responseStatusCode! > 0;

  bool get isAccepted {
    final code = responseStatusCode;
    return code != null && code >= 200 && code < 300;
  }

  PhotoUploadItem copyForImmediateRetry(int nowMillis) => PhotoUploadItem(
        id: id,
        sessionId: sessionId,
        angleId: angleId,
        photoIndex: photoIndex,
        imageOrder: imageOrder,
        captureSessionId: captureSessionId,
        isCallEngine: isCallEngine,
        filePath: filePath,
        fileName: fileName,
        fileField: fileField,
        url: url,
        headers: headers,
        fields: fields,
        createdAtMillis: createdAtMillis,
        updatedAtMillis: nowMillis,
        status: PhotoUploadStatus.pending,
        lastError: lastError,
        errorType: errorType,
        lastFailedAtMillis: lastFailedAtMillis,
        lastStatusCode: lastStatusCode,
      );

  factory PhotoUploadItem.fromJson(Map<String, dynamic> json) {
    return PhotoUploadItem(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      angleId: json['angleId'] as int,
      photoIndex: json['photoIndex'] as int,
      imageOrder: json['imageOrder'] as int?,
      captureSessionId: json['captureSessionId'] as String? ??
          (json['fields'] is Map
              ? (json['fields'] as Map)['captureSessionId'] as String?
              : null),
      isCallEngine:
          json['isCallEngine'] as bool? ?? json['isCapture'] as bool? ?? false,
      filePath: json['filePath'] as String,
      fileName: json['fileName'] as String,
      fileField: json['fileField'] as String,
      url: json['url'] as String,
      headers: _stringMap(json['headers']),
      fields: _stringMap(json['fields']),
      status: PhotoUploadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => PhotoUploadStatus.pending,
      ),
      attempt: json['attempt'] as int? ?? 0,
      nextAttemptAtMillis: json['nextAttemptAtMillis'] as int? ?? 0,
      createdAtMillis: json['createdAtMillis'] as int? ?? 0,
      updatedAtMillis: json['updatedAtMillis'] as int? ?? 0,
      lastError: json['lastError'] as String?,
      errorType: json['errorType'] as String?,
      lastFailedAtMillis: json['lastFailedAtMillis'] as int?,
      lastStatusCode: json['lastStatusCode'] as int?,
      responseBody: json['responseBody'] as String?,
      responseStatusCode: json['responseStatusCode'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'angleId': angleId,
        'photoIndex': photoIndex,
        if (imageOrder != null) 'imageOrder': imageOrder,
        if (captureSessionId != null) 'captureSessionId': captureSessionId,
        'isCallEngine': isCallEngine,
        'filePath': filePath,
        'fileName': fileName,
        'fileField': fileField,
        'url': url,
        'headers': headers,
        'fields': fields,
        'status': status.name,
        'attempt': attempt,
        'nextAttemptAtMillis': nextAttemptAtMillis,
        'createdAtMillis': createdAtMillis,
        'updatedAtMillis': updatedAtMillis,
        if (lastError != null) 'lastError': lastError,
        if (errorType != null) 'errorType': errorType,
        if (lastFailedAtMillis != null)
          'lastFailedAtMillis': lastFailedAtMillis,
        if (lastStatusCode != null) 'lastStatusCode': lastStatusCode,
        if (responseBody != null) 'responseBody': responseBody,
        if (responseStatusCode != null)
          'responseStatusCode': responseStatusCode,
      };

  Map<String, dynamic> toPlatformMap({String? queueFilePath}) => {
        'id': id,
        'filePath': filePath,
        'fileName': fileName,
        'fileField': fileField,
        'url': url,
        'headers': headers,
        'fields': fields,
        'attempt': attempt,
        'nextAttemptAtMillis': nextAttemptAtMillis,
        // iOS sends captured photos ahead of context-stream frames.
        'isCallEngine': isCallEngine,
        if (queueFilePath != null) 'queueFilePath': queueFilePath,
      };

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) return {};
    return {
      for (final entry in value.entries)
        entry.key.toString(): entry.value.toString(),
    };
  }
}

enum PhotoUploadStatus {
  pending,
  uploading,
  succeeded,
  skipped,

  /// The server answered with a non-retryable error for this photo.
  rejected,
  failed;

  bool get isTerminal =>
      this == succeeded || this == skipped || this == rejected;
}

enum UploadMode { background, fast }

const _failureStreakKey = 'failureStreak';

/// Consecutive captured-photo upload failures since the server last answered.
class UploadFailureStreak {
  const UploadFailureStreak({
    required this.sinceMillis,
    required this.count,
    required this.timeoutCount,
    required this.itemIds,
    this.lastErrorType,
  });

  factory UploadFailureStreak.fromJson(Map<String, dynamic> json) {
    final ids = json['itemIds'];
    return UploadFailureStreak(
      sinceMillis: json['sinceMillis'] as int? ?? 0,
      count: json['count'] as int? ?? 0,
      timeoutCount: json['timeoutCount'] as int? ?? 0,
      itemIds: ids is List ? ids.map((e) => e.toString()).toSet() : const {},
      lastErrorType: json['lastErrorType'] as String?,
    );
  }

  final int sinceMillis;

  /// Failed requests in the streak (retries of one photo count separately).
  final int count;

  /// Trailing run of timeouts within [count].
  final int timeoutCount;

  /// Distinct photos that failed during the streak.
  final Set<String> itemIds;
  final String? lastErrorType;
}

class UploadHealthSnapshot {
  const UploadHealthSnapshot({
    required this.pending,
    required this.failing,
    this.streak,
    this.lastSuccessAtMillis,
    this.lastResponseAtMillis,
    this.pendingQueuedAtMillis = const [],
  });

  /// Captured photos of the session still waiting to reach the server.
  final int pending;

  /// Of [pending], how many are waiting on a retry.
  final int failing;
  final UploadFailureStreak? streak;
  final int? lastSuccessAtMillis;

  /// Last time the server answered anything (any photo or stream frame, any
  /// HTTP status): proof that the connection is alive.
  final int? lastResponseAtMillis;

  /// When each of the [pending] captured photos was queued.
  final List<int> pendingQueuedAtMillis;
}

class _QueueDocument {
  const _QueueDocument({required this.meta, required this.items});

  _QueueDocument.empty()
      : meta = const {},
        items = const [];

  final Map<String, dynamic> meta;
  final List<PhotoUploadItem> items;
}

class UploadQueueProgress {
  const UploadQueueProgress({
    required this.total,
    required this.uploaded,
    required this.pending,
  });

  final int total;
  final int uploaded;
  final int pending;
}

class _UploadResponseListener {
  _UploadResponseListener({
    required this.sessionId,
    required this.onData,
    required this.keepAliveAfterRemove,
  });

  static const detachedKeepAlive = Duration(minutes: 30);

  final String? sessionId;
  final void Function(Map<String, dynamic> data) onData;
  final bool keepAliveAfterRemove;
  DateTime? detachedAt;

  bool matches(String itemSessionId) =>
      sessionId == null || sessionId == itemSessionId;

  bool hasWorkFor(PhotoUploadItem item) {
    if (!matches(item.sessionId)) return false;
    return item.hasPendingResponse || !item.status.isTerminal;
  }
}

class _UploadRequest {
  const _UploadRequest({
    required this.url,
    required this.fileField,
    required this.headers,
    required this.fields,
  });

  final String url;
  final String fileField;
  final Map<String, String> headers;
  final Map<String, String> fields;
}

class _PhotoFileStat {
  const _PhotoFileStat({required this.file, required this.stat});

  final File file;
  final FileStat stat;
}

class _ExistingPhotoInfo {
  const _ExistingPhotoInfo({
    required this.angleId,
    required this.photoIndex,
    required this.path,
  });

  final int angleId;
  final int photoIndex;
  final String path;
}
