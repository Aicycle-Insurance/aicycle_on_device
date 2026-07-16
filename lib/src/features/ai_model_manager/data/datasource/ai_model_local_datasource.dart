import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../../core/error/exceptions.dart';
import '../../domain/entity/ai_model_type.dart';
import '../model/ai_model.dart';
import '../model/downloaded_model_info.dart';
import '../model/model_manifest.dart';

/// Quản lý file model trong bộ nhớ nội bộ của app
/// (Application Support — user không truy cập được từ Files/Gallery).
///
/// Cấu trúc lưu trữ:
/// ```
/// <app_support>/aicycle_models/
///   manifest.json                  # model đã tải + model đang chọn
///   CarCorner/<id>_<modelName>     # file model theo từng loại
///   CarDamage/...
///   CarPart/...
/// ```
class AiModelLocalDataSource {
  static const _rootDirName = 'aicycle_models';
  static const _manifestFileName = 'manifest.json';

  Future<Directory> _rootDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_rootDirName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _manifestFile() async {
    final root = await _rootDir();
    return File('${root.path}/$_manifestFileName');
  }

  Future<ModelManifest> readManifest() async {
    try {
      final file = await _manifestFile();
      if (!await file.exists()) return ModelManifest.empty();
      final json = jsonDecode(await file.readAsString());
      final manifest = ModelManifest.fromJson(json as Map<String, dynamic>);
      // Manifest lưu đường dẫn tương đối; resolve về tuyệt đối theo thư mục
      // hiện tại vì đường dẫn sandbox (iOS) đổi sau mỗi lần cài lại app
      final root = await _rootDir();
      return manifest.copyWith(
        downloaded: manifest.downloaded
            .map(
              (e) => e.copyWith(
                filePath: '${root.path}/${_relativePathOf(e)}',
              ),
            )
            .toList(),
      );
    } catch (e) {
      throw CacheException('Failed to read model manifest: $e');
    }
  }

  Future<void> _writeManifest(ModelManifest manifest) async {
    try {
      final file = await _manifestFile();
      // Chỉ lưu đường dẫn tương đối để không phụ thuộc sandbox path
      final normalized = manifest.copyWith(
        downloaded: manifest.downloaded
            .map((e) => e.copyWith(filePath: _relativePathOf(e)))
            .toList(),
      );
      await file.writeAsString(jsonEncode(normalized.toJson()));
    } catch (e) {
      throw CacheException('Failed to write model manifest: $e');
    }
  }

  /// Đường dẫn tương đối trong thư mục model: `<type>/<tên file>`.
  /// Chấp nhận cả path tuyệt đối (manifest phiên bản cũ) lẫn tương đối.
  String _relativePathOf(DownloadedModelInfo info) {
    final fileName = info.filePath.split('/').last;
    return '${info.type.apiValue}/$fileName';
  }

  /// Đường dẫn file tạm dùng trong quá trình tải.
  Future<String> createTempFilePath(AiModel model) async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/${model.id}_${model.modelName}.part';
  }

  /// Chuyển file đã tải xong từ thư mục tạm vào bộ nhớ nội bộ
  /// và ghi nhận vào manifest.
  Future<DownloadedModelInfo> persistDownloadedModel(
    AiModel model,
    String tempPath,
  ) async {
    try {
      final root = await _rootDir();
      final typeDir = Directory('${root.path}/${model.type.apiValue}');
      if (!await typeDir.exists()) {
        await typeDir.create(recursive: true);
      }

      // Lưu với tên modelName (không thêm .zip) để path trong manifest
      // khớp với tên sau khi YOLOModelResolver giải nén (.mlpackage directory).
      final fileName = '${model.id}_${model.modelName}';
      final destPath = '${typeDir.path}/$fileName';

      final tempFile = File(tempPath);
      try {
        await tempFile.rename(destPath);
      } on FileSystemException {
        // rename thất bại khi temp và app support nằm khác volume
        await tempFile.copy(destPath);
        await tempFile.delete();
      }

      final info = DownloadedModelInfo.fromModel(
        model,
        destPath,
        sizeInBytes: await File(destPath).length(),
      );
      final manifest = await readManifest();
      final downloaded = [
        ...manifest.downloaded.where((e) => e.id != info.id),
        info,
      ];
      await _writeManifest(manifest.copyWith(downloaded: downloaded));
      return info;
    } on CacheException {
      rethrow;
    } catch (e) {
      throw CacheException('Failed to persist model: $e');
    }
  }

  /// Xoá file model và cập nhật manifest. Nếu model đang được chọn,
  /// tự chuyển selection sang model khác cùng loại (nếu có).
  Future<ModelManifest> deleteModel(int modelId) async {
    try {
      final manifest = await readManifest();
      final target =
          manifest.downloaded.where((e) => e.id == modelId).firstOrNull;
      if (target == null) return manifest;

      // Path có thể là file (chưa giải nén) hoặc directory (đã giải nén bởi YOLOModelResolver)
      final entity = FileSystemEntity.typeSync(target.filePath);
      if (entity == FileSystemEntityType.file) {
        await File(target.filePath).delete();
      } else if (entity == FileSystemEntityType.directory) {
        await Directory(target.filePath).delete(recursive: true);
      }

      final downloaded =
          manifest.downloaded.where((e) => e.id != modelId).toList();
      final selected = Map<AiModelType, int?>.from(manifest.selected);
      if (selected[target.type] == modelId) {
        selected[target.type] =
            downloaded.where((e) => e.type == target.type).firstOrNull?.id;
      }

      final updated = ModelManifest(selected: selected, downloaded: downloaded);
      await _writeManifest(updated);
      return updated;
    } on CacheException {
      rethrow;
    } catch (e) {
      throw CacheException('Failed to delete model: $e');
    }
  }

  /// Xoá toàn bộ model đã tải và reset manifest.
  Future<void> deleteAllModels() async {
    try {
      final root = await _rootDir();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    } catch (e) {
      throw CacheException('Failed to delete all models: $e');
    }
  }

  /// Ghi nhận model [modelId] đã validate thành công với metadata task
  /// [validatedTask] (chuỗi rỗng nếu model không có task — vd OCR biển số).
  Future<void> markModelValidated(int modelId, String validatedTask) async {
    final manifest = await readManifest();
    final downloaded = manifest.downloaded
        .map(
          (e) => e.id == modelId ? e.copyWith(validatedTask: validatedTask) : e,
        )
        .toList();
    await _writeManifest(manifest.copyWith(downloaded: downloaded));
  }

  /// Lưu model được chọn cho loại tương ứng.
  Future<void> setSelectedModel(AiModelType type, int modelId) async {
    final manifest = await readManifest();
    final selected = Map<AiModelType, int?>.from(manifest.selected);
    selected[type] = modelId;
    await _writeManifest(manifest.copyWith(selected: selected));
  }
}
