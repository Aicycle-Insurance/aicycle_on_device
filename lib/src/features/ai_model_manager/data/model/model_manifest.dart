import '../../domain/entity/ai_model_type.dart';
import 'downloaded_model_info.dart';

/// Trạng thái lưu trữ local của các model: danh sách đã tải
/// và model đang được chọn cho từng loại.
///
/// Được lưu dưới dạng file `manifest.json` trong thư mục model.
class ModelManifest {
  /// Model id đang được chọn cho từng loại (null = chưa chọn).
  final Map<AiModelType, int?> selected;

  /// Danh sách model đã tải về.
  final List<DownloadedModelInfo> downloaded;

  const ModelManifest({required this.selected, required this.downloaded});

  factory ModelManifest.empty() {
    return ModelManifest(
      selected: {for (final type in AiModelType.values) type: null},
      downloaded: const [],
    );
  }

  factory ModelManifest.fromJson(Map<String, dynamic> json) {
    final selectedJson = json['selected'] as Map<String, dynamic>? ?? {};
    final downloadedJson = json['downloaded'] as List<dynamic>? ?? [];
    return ModelManifest(
      selected: {
        for (final type in AiModelType.values)
          type: selectedJson[type.apiValue] as int?,
      },
      downloaded: downloadedJson
          .map((e) => DownloadedModelInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'selected': {
        for (final entry in selected.entries)
          if (entry.value != null) entry.key.apiValue: entry.value,
      },
      'downloaded': downloaded.map((e) => e.toJson()).toList(),
    };
  }

  ModelManifest copyWith({
    Map<AiModelType, int?>? selected,
    List<DownloadedModelInfo>? downloaded,
  }) {
    return ModelManifest(
      selected: selected ?? this.selected,
      downloaded: downloaded ?? this.downloaded,
    );
  }
}
