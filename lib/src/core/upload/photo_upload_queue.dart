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

  final Map<Object, _UploadResponseListener> _responseListeners = {};
  Timer? _responseDeliveryTimer;
  bool _isDrainingResponses = false;
  Future<void> _mutationTail = Future<void>.value();
  int _tempFileSequence = 0;

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
        if (listener == null) continue;

        final data = _decodeResponseMap(item);
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
    bool isCallEngine = true,
    double? latitude,
    double? longitude,
  }) =>
      _enqueuePhoto(
        sessionId: sessionId,
        angleId: angleId,
        photoIndex: photoIndex,
        filePath: filePath,
        imageOrder: imageOrder,
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
    bool isCallEngine = true,
    double? latitude,
    double? longitude,
    required bool schedule,
  }) async {
    final request = _buildUploadRequest();
    final fields = {
      ...request.fields,
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
      if (imageOrder != null) 'imageOrder': imageOrder.toString(),
      'isCallEngine': isCallEngine ? 'true' : 'false',
    };
    final fileName = '${angleId}_$photoIndex.jpg';
    final item = PhotoUploadItem(
      id: _stableId('$sessionId|$angleId|$filePath'),
      sessionId: sessionId,
      angleId: angleId,
      photoIndex: photoIndex,
      imageOrder: imageOrder,
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

    await _mutateItems((items) => [
          for (final existing in items)
            if (existing.id != item.id) existing,
          item,
        ]);
    debugPrint(
      'AICycle upload queued: session=$sessionId angle=$angleId '
      'photo=$photoIndex imageOrder=$imageOrder isCallEngine=$isCallEngine '
      'file=${item.fileName}',
    );
    await enforceCacheLimit();
    if (schedule) await _schedulePendingUploadsBestEffort();
  }

  Future<void> enqueueExistingPhotos(
    String sessionId,
    Map<int, List<String>> photoPaths,
  ) async {
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
        isCallEngine: true,
        schedule: false,
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

  Future<List<PhotoUploadItem>> _readItems() async {
    final file = await _metadataFile();
    if (!file.existsSync()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return [];
      final rawItems = decoded['items'];
      if (rawItems is! List) return [];
      return rawItems
          .whereType<Map>()
          .map((e) => PhotoUploadItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeItems(List<PhotoUploadItem> items) async {
    final file = await _metadataFile(create: true);
    final tmp = File(
      '${file.path}.dart-$pid-${DateTime.now().microsecondsSinceEpoch}-'
      '${_tempFileSequence++}.tmp',
    );
    try {
      await tmp.writeAsString(
        jsonEncode({
          'version': 1,
          'items': [for (final item in items) item.toJson()],
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
      _withMutationLock(() async {
        final latestItems = await _readItems();
        final nextItems = mutate(latestItems);
        await _writeItems(nextItems);
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

  Future<void> schedulePendingUploads() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final file = await _metadataFile(create: true);

    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('schedulePhotoUploadQueue', {
        'queueFilePath': file.path,
      });
      debugPrint('AICycle upload scheduled on Android WorkManager');
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final items = (await _readItems()).where(
      (item) =>
          !item.status.isTerminal &&
          item.nextAttemptAtMillis <= now &&
          File(item.filePath).existsSync(),
    );
    for (final item in items) {
      await _channel.invokeMethod<void>(
        'schedulePhotoUpload',
        item.toPlatformMap(queueFilePath: file.path),
      );
      debugPrint(
        'AICycle upload scheduled on iOS URLSession: '
        'angle=${item.angleId} photo=${item.photoIndex}',
      );
    }
  }

  Future<void> _schedulePendingUploadsBestEffort() async {
    try {
      await schedulePendingUploads();
    } on PlatformException catch (error) {
      // The queue item is already durable on disk. A lifecycle resume or the
      // next capture will schedule it again, so a transient platform-channel
      // failure must not turn a successfully captured photo into a failure.
      debugPrint('AICycle upload scheduling deferred: ${error.message}');
    }
  }

  _UploadRequest _buildUploadRequest() {
    final config = AICycleConfigHolder.config;
    final sessionId = config.generalConfig.documentId;

    if (config.generalConfig.organization == AiCycleOrg.vbi) {
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

  Map<String, dynamic> _decodeResponseMap(PhotoUploadItem item) {
    final body = item.responseBody?.trim() ?? '';
    if (body.isEmpty) return _fallbackUploadResponse(item);
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Non-JSON success bodies still mean the upload reached the server.
    }
    return _fallbackUploadResponse(item, rawBody: body);
  }

  Map<String, dynamic> _fallbackUploadResponse(
    PhotoUploadItem item, {
    String? rawBody,
  }) {
    return {
      'uploaded': true,
      'statusCode': item.responseStatusCode,
      'sessionId': item.sessionId,
      'angleId': item.angleId,
      'photoIndex': item.photoIndex,
      'fileName': item.fileName,
      if (rawBody != null && rawBody.isNotEmpty) 'rawBody': rawBody,
    };
  }
}

class PhotoUploadItem {
  PhotoUploadItem({
    required this.id,
    required this.sessionId,
    required this.angleId,
    required this.photoIndex,
    this.imageOrder,
    this.isCallEngine = true,
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
    this.responseBody,
    this.responseStatusCode,
  });

  final String id;
  final String sessionId;
  final int angleId;
  final int photoIndex;
  final int? imageOrder;
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
  final String? responseBody;
  final int? responseStatusCode;

  bool get hasPendingResponse =>
      status == PhotoUploadStatus.succeeded &&
      responseStatusCode != null &&
      responseStatusCode! > 0;

  factory PhotoUploadItem.fromJson(Map<String, dynamic> json) {
    return PhotoUploadItem(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      angleId: json['angleId'] as int,
      photoIndex: json['photoIndex'] as int,
      imageOrder: json['imageOrder'] as int?,
      isCallEngine:
          json['isCallEngine'] as bool? ?? json['isCapture'] as bool? ?? true,
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
  failed;

  bool get isTerminal => this == succeeded || this == skipped;
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
