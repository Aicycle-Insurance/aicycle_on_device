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

  Future<Directory> _angleDir(String sessionId, int angleId) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_rootDirName/$sessionId/$angleId');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// Saves [bytes] for the given [sessionId] and [angleId].
  Future<void> savePhoto(
      String sessionId, int angleId, Uint8List bytes) async {
    final dir = await _angleDir(sessionId, angleId);
    final path = '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(path).writeAsBytes(bytes);
  }

  /// Loads all previously saved photos for [sessionId].
  /// Returns a map of angleId → ordered list of JPEG bytes.
  Future<Map<int, List<Uint8List>>> loadSession(String sessionId) async {
    final base = await getApplicationSupportDirectory();
    final sessionDir =
        Directory('${base.path}/$_rootDirName/$sessionId');
    if (!sessionDir.existsSync()) return {};

    final result = <int, List<Uint8List>>{};
    for (final entity in sessionDir.listSync()) {
      if (entity is! Directory) continue;
      final angleId = int.tryParse(entity.path.split('/').last);
      if (angleId == null) continue;
      final files = entity.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path)); // order by timestamp
      if (files.isEmpty) continue;
      result[angleId] = [
        for (final f in files) await f.readAsBytes(),
      ];
    }
    return result;
  }

  /// Deletes all cached photos for [sessionId].
  Future<void> clearSession(String sessionId) async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_rootDirName/$sessionId');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }

  /// Deletes the entire photo cache directory.
  Future<void> clearAll() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_rootDirName');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }
}
