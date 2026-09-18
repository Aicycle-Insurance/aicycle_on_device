import 'dart:convert';
import 'package:flutter/services.dart';

import '../../domain/entity/ai_model_type.dart';

/// Khai báo cấu hình của một model trong manifest khai báo ngoài.
class DeclaredModelItem {
  final String version;
  final int? id;
  final String? modelName;

  const DeclaredModelItem({
    required this.version,
    this.id,
    this.modelName,
  });

  factory DeclaredModelItem.fromJson(Map<String, dynamic> json) {
    return DeclaredModelItem(
      version: (json['version'] as Object).toString(),
      id: json['id'] as int?,
      modelName: json['modelName'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      if (id != null) 'id': id,
      if (modelName != null) 'modelName': modelName,
    };
  }

  @override
  String toString() =>
      'DeclaredModelItem(version: $version, id: $id, modelName: $modelName)';
}

/// Manifest khai báo danh sách model cần tải và sử dụng cho từng loại.
class DeclaredModelManifest {
  final Map<AiModelType, DeclaredModelItem> models;

  const DeclaredModelManifest({required this.models});

  factory DeclaredModelManifest.empty() =>
      const DeclaredModelManifest(models: {});

  factory DeclaredModelManifest.fromJson(Map<String, dynamic> json) {
    final modelsJson = json['models'] as Map<String, dynamic>? ?? json;
    final map = <AiModelType, DeclaredModelItem>{};

    for (final type in AiModelType.values) {
      // Hỗ trợ cả key dạng enum name (carCorner) lẫn apiValue (CarCorner)
      final itemJson = modelsJson[type.name] ?? modelsJson[type.apiValue];
      if (itemJson is Map<String, dynamic>) {
        map[type] = DeclaredModelItem.fromJson(itemJson);
      }
    }

    return DeclaredModelManifest(models: map);
  }

  /// Tải file manifest từ assets.
  /// Thử lần lượt các đường dẫn khả dĩ (bao gồm đường dẫn do user cung cấp,
  /// đường dẫn bundle từ package và đường dẫn root).
  static Future<DeclaredModelManifest> loadFromAsset([String? assetPath]) async {
    final candidates = [
      if (assetPath != null && assetPath.isNotEmpty) assetPath,
      'packages/aicycle_on_device/assets/models_manifest.json',
      'assets/models_manifest.json',
    ];

    for (final path in candidates) {
      try {
        final jsonStr = await rootBundle.loadString(path);
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        return DeclaredModelManifest.fromJson(data);
      } catch (_) {
        // Thử đường dẫn tiếp theo
      }
    }

    return DeclaredModelManifest.empty();
  }
}
