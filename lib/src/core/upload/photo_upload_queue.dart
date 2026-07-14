import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  Future<void> enqueuePhoto({
    required String sessionId,
    required int angleId,
    required int photoIndex,
    required String filePath,
  }) async {
    final request = _buildUploadRequest();
    final item = PhotoUploadItem(
      id: _stableId('$sessionId|$angleId|$filePath'),
      sessionId: sessionId,
      angleId: angleId,
      photoIndex: photoIndex,
      filePath: filePath,
      fileName: '${angleId}_$photoIndex.jpg',
      fileField: request.fileField,
      url: request.url,
      headers: request.headers,
      fields: request.fields,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
      updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    final items = await _readItems();
    final next = [
      for (final existing in items)
        if (existing.id != item.id) existing,
      item,
    ];
    await _writeItems(next);
    await enforceCacheLimit();
    unawaited(schedulePendingUploads());
  }

  Future<void> enqueueExistingPhotos(
    String sessionId,
    Map<int, List<String>> photoPaths,
  ) async {
    for (final entry in photoPaths.entries) {
      for (var i = 0; i < entry.value.length; i++) {
        final path = entry.value[i];
        if (!File(path).existsSync()) continue;
        await enqueuePhoto(
          sessionId: sessionId,
          angleId: entry.key,
          photoIndex: i,
          filePath: path,
        );
      }
    }
  }

  Future<void> resumePendingUploads() async {
    await _removeMissingOrSucceededItems();
    await schedulePendingUploads();
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
    final items = await _readItems();
    await _writeItems([
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
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'version': 1,
      'items': [for (final item in items) item.toJson()],
    }));
    if (file.existsSync()) await file.delete();
    await tmp.rename(file.path);
  }

  Future<void> _removeMissingOrSucceededItems() async {
    final items = await _readItems();
    final kept = [
      for (final item in items)
        if (!item.status.isTerminal && File(item.filePath).existsSync()) item,
    ];
    if (kept.length != items.length) await _writeItems(kept);
  }

  Future<void> schedulePendingUploads() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    final file = await _metadataFile(create: true);

    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('schedulePhotoUploadQueue', {
        'queueFilePath': file.path,
      });
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
        item.toPlatformMap(),
      );
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
}

class PhotoUploadItem {
  PhotoUploadItem({
    required this.id,
    required this.sessionId,
    required this.angleId,
    required this.photoIndex,
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
  });

  final String id;
  final String sessionId;
  final int angleId;
  final int photoIndex;
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

  factory PhotoUploadItem.fromJson(Map<String, dynamic> json) {
    return PhotoUploadItem(
      id: json['id'] as String,
      sessionId: json['sessionId'] as String,
      angleId: json['angleId'] as int,
      photoIndex: json['photoIndex'] as int,
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
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'angleId': angleId,
        'photoIndex': photoIndex,
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
      };

  Map<String, dynamic> toPlatformMap() => {
        'id': id,
        'filePath': filePath,
        'fileName': fileName,
        'fileField': fileField,
        'url': url,
        'headers': headers,
        'fields': fields,
        'attempt': attempt,
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
