import '../../domain/entity/ai_model_type.dart';

/// Model AI trả về từ API danh sách model.
class AiModel {
  final int id;
  final String modelName;
  final String version;
  final AiModelType type;
  final DateTime createdDate;
  final DateTime updatedDate;
  final String modelDownloadUrl;
  final String? modelOs;

  const AiModel({
    required this.id,
    required this.modelName,
    required this.version,
    required this.type,
    required this.createdDate,
    required this.updatedDate,
    required this.modelDownloadUrl,
    this.modelOs,
  });

  factory AiModel.fromJson(Map<String, dynamic> json) {
    return AiModel(
      id: json['id'] as int,
      modelName: json['modelName'] as String,
      version: json['version'] as String,
      type: AiModelType.fromApi(json['type'] as String),
      createdDate: DateTime.parse(json['createdDate'] as String),
      updatedDate: DateTime.parse(json['updatedDate'] as String),
      modelDownloadUrl: json['modelDownloadUrl'] as String,
      modelOs: json['modelOs'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'modelName': modelName,
      'version': version,
      'type': type.apiValue,
      'createdDate': createdDate.toIso8601String(),
      'updatedDate': updatedDate.toIso8601String(),
      'modelDownloadUrl': modelDownloadUrl,
      'modelOs': modelOs,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiModel && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'AiModel(id: $id, version: $version, type: ${type.apiValue})';
}
