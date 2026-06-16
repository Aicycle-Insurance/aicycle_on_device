import 'dart:io';

import '../../../../core/network/dio_client.dart';
import '../../domain/entity/ai_model_type.dart';
import '../model/ai_model.dart';

/// Gọi API server: danh sách model + tải file model.
class AiModelRemoteDataSource {
  AiModelRemoteDataSource(this._client);

  final DioClient _client;

  /// Hệ điều hành hiện tại gửi lên API để lấy link tải model tương ứng.
  static final String _modelOs = Platform.isIOS ? 'ios' : 'android';

  /// GET /v2/model-edge-device?modelType=...&modelOs=...
  /// baseUrl và token được DioClient tự gắn theo môi trường trong config.
  Future<List<AiModel>> getModels(AiModelType type) async {
    final data = await _client.get<Map<String, dynamic>>(
      '/insurance/v2/model-edge-device',
      queryParameters: {
        'modelType': type.apiValue,
        'modelOs': _modelOs,
      },
    );
    final records = data['records'] as List<dynamic>? ?? [];
    return records
        .map((e) => AiModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Lấy kích thước file model (bytes) qua Content-Length,
  /// null nếu không xác định được.
  Future<int?> getFileSize(String url) {
    return _client.getContentLength(url);
  }

  /// Tải file model về [savePath]. [onProgress] nhận giá trị 0.0 → 1.0.
  Future<void> downloadFile(
    String url,
    String savePath, {
    void Function(double progress)? onProgress,
  }) {
    return _client.download(
      url,
      savePath,
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );
  }
}
