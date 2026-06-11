import '../../domain/entity/ai_model_type.dart';
import 'ai_model.dart';

/// Thông tin một model đã được tải về máy.
class DownloadedModelInfo {
  final int id;
  final String modelName;
  final String version;
  final AiModelType type;

  /// Đường dẫn file model trong bộ nhớ nội bộ của app.
  final String filePath;

  /// Kích thước file (bytes), null nếu không xác định được.
  final int? sizeInBytes;
  final DateTime createdDate;
  final DateTime downloadedAt;

  const DownloadedModelInfo({
    required this.id,
    required this.modelName,
    required this.version,
    required this.type,
    required this.filePath,
    required this.createdDate,
    required this.downloadedAt,
    this.sizeInBytes,
  });

  factory DownloadedModelInfo.fromModel(
    AiModel model,
    String filePath, {
    int? sizeInBytes,
  }) {
    return DownloadedModelInfo(
      id: model.id,
      modelName: model.modelName,
      version: model.version,
      type: model.type,
      filePath: filePath,
      sizeInBytes: sizeInBytes,
      createdDate: model.createdDate,
      downloadedAt: DateTime.now(),
    );
  }

  factory DownloadedModelInfo.fromJson(Map<String, dynamic> json) {
    return DownloadedModelInfo(
      id: json['id'] as int,
      modelName: json['modelName'] as String,
      version: json['version'] as String,
      type: AiModelType.fromApi(json['type'] as String),
      filePath: json['filePath'] as String,
      sizeInBytes: json['sizeInBytes'] as int?,
      createdDate: DateTime.parse(json['createdDate'] as String),
      downloadedAt: DateTime.parse(json['downloadedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'modelName': modelName,
      'version': version,
      'type': type.apiValue,
      'filePath': filePath,
      'sizeInBytes': sizeInBytes,
      'createdDate': createdDate.toIso8601String(),
      'downloadedAt': downloadedAt.toIso8601String(),
    };
  }
}
