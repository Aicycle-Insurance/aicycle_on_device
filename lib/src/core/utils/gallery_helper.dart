import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/config_holder.dart';

/// Tiện ích lưu ảnh vào thư viện ảnh của thiết bị.
///
/// Chỉ hoạt động khi `generalConfig.savePhotoAfterShot = true`.
class GalleryHelper {
  GalleryHelper._();

  /// Xin quyền truy cập thư viện ảnh sớm để khi lưu không bị block bởi
  /// dialog xin quyền. Gọi một lần trước khi bắt đầu lưu ảnh.
  static Future<void> requestPermission() async {
    if (!AICycleConfigHolder.config.generalConfig.savePhotoAfterShot) return;
    try {
      // iOS: photosAddOnly (NSPhotoLibraryAddUsageDescription).
      // Android: storage (API ≤ 32) — bản mới không cần quyền để ghi DCIM.
      final permission =
          Platform.isIOS ? Permission.photosAddOnly : Permission.storage;
      final status = await permission.status;
      if (status.isDenied) {
        await permission.request();
      }
    } catch (e) {
      debugPrint('Failed to request gallery permission: $e');
    }
  }

  /// Lưu ảnh (JPEG bytes) vào thư viện ảnh của thiết bị.
  static Future<void> saveBytes(Uint8List bytes) async {
    if (!AICycleConfigHolder.config.generalConfig.savePhotoAfterShot) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/aicycle_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      await GallerySaver.saveImage(file.path);
      // Dọn temp file sau khi đã lưu vào gallery.
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Failed to save to gallery: $e');
    }
  }
}
