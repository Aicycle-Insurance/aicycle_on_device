import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Persists captured photos to disk keyed by [sessionId] (documentId) and angleId.
///
/// Layout:
/// ```
/// <app_support>/aicycle_photo_cache/
///   <sessionId>/
///     <angleId>/
///       <timestamp_ms>.jpg
/// ```
///
/// Survives app kills. Call [clearSession] after successful upload or when
/// the user intentionally abandons the session.
class PhotoSessionCache {
  PhotoSessionCache._();
  static final PhotoSessionCache instance = PhotoSessionCache._();

  static const _rootDirName = 'aicycle_photo_cache';
  static const _uploadPendingFileName = '.upload_pending';
  static const _thumbnailDirName = '.thumbs';

  static String thumbnailPathForPhotoPath(String photoPath) {
    final file = File(photoPath);
    return '${file.parent.path}/$_thumbnailDirName/${file.uri.pathSegments.last}';
  }

  Future<Directory> rootDir({bool create = false}) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_rootDirName');
    if (create && !dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<Directory> _sessionDir(
    String sessionId, {
    bool create = false,
  }) async {
    final root = await rootDir(create: create);
    final dir = Directory('${root.path}/$sessionId');
    if (create && !dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<Directory> _angleDir(String sessionId, int angleId) async {
    final sessionDir = await _sessionDir(sessionId, create: true);
    final dir = Directory('${sessionDir.path}/$angleId');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Creates a unique JPEG path for a captured photo.
  Future<String> createPhotoPath(String sessionId, int angleId) async {
    final dir = await _angleDir(sessionId, angleId);
    final micros = DateTime.now().microsecondsSinceEpoch;
    return '${dir.path}/$micros.jpg';
  }

  /// Creates a directory for one burst capture (JPEG files keyed by stepIndex).
  Future<String> createBurstDir(String sessionId) async {
    final sessionDir = await _sessionDir(sessionId, create: true);
    final micros = DateTime.now().microsecondsSinceEpoch;
    final dir = Directory('${sessionDir.path}/burst_$micros');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  /// Saves [bytes] for the given [sessionId] and [angleId].
  Future<String> savePhoto(
      String sessionId, int angleId, Uint8List bytes) async {
    final path = await createPhotoPath(sessionId, angleId);
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Loads all previously saved photo paths for [sessionId].
  /// Returns a map of angleId -> ordered list of JPEG file paths.
  Future<Map<int, List<String>>> loadSessionPhotoPaths(String sessionId) async {
    final sessionDir = await _sessionDir(sessionId);
    if (!sessionDir.existsSync()) return {};

    final result = <int, List<String>>{};
    for (final entity in sessionDir.listSync()) {
      if (entity is! Directory) continue;
      final angleId = int.tryParse(entity.path.split('/').last);
      if (angleId == null) continue;
      final files = entity.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path)); // order by timestamp
      if (files.isEmpty) continue;
      result[angleId] = [for (final f in files) f.path];
    }
    return result;
  }

  /// Loads all previously saved photos for [sessionId].
  /// Returns a map of angleId -> ordered list of JPEG bytes.
  Future<Map<int, List<Uint8List>>> loadSession(String sessionId) async {
    final paths = await loadSessionPhotoPaths(sessionId);
    return {
      for (final entry in paths.entries)
        entry.key: [
          for (final path in entry.value) await File(path).readAsBytes(),
        ],
    };
  }

  /// Deletes all cached photos for a single [angleId] within [sessionId].
  Future<void> clearAngle(String sessionId, int angleId) async {
    final sessionDir = await _sessionDir(sessionId);
    final dir = Directory('${sessionDir.path}/$angleId');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Deletes all cached photos for [sessionId].
  Future<void> clearSession(String sessionId) async {
    final dir = await _sessionDir(sessionId);
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  Future<void> markUploadPending(String sessionId) async {
    final sessionDir = await _sessionDir(sessionId, create: true);
    final marker = File('${sessionDir.path}/$_uploadPendingFileName');
    await marker.writeAsString(DateTime.now().toIso8601String());
  }

  Future<void> clearUploadPending(String sessionId) async {
    final sessionDir = await _sessionDir(sessionId);
    final marker = File('${sessionDir.path}/$_uploadPendingFileName');
    if (marker.existsSync()) await marker.delete();
  }

  Future<bool> isUploadPending(String sessionId) async {
    final sessionDir = await _sessionDir(sessionId);
    final marker = File('${sessionDir.path}/$_uploadPendingFileName');
    return marker.existsSync();
  }

  Future<bool> hasSessionData(String sessionId) async {
    final sessionDir = await _sessionDir(sessionId);
    if (!sessionDir.existsSync()) return false;
    final marker = File('${sessionDir.path}/$_uploadPendingFileName');
    if (marker.existsSync()) return true;
    for (final entity in sessionDir.listSync()) {
      if (entity is Directory &&
          entity.listSync().whereType<File>().isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Deletes the entire photo cache directory.
  Future<void> clearAll() async {
    final dir = await rootDir();
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
