import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../core/network/dio_client.dart';

class ResultRemoteDataSource {
  ResultRemoteDataSource(this._client);

  final DioClient _client;

  /// TODO: replace path and field names once endpoint is confirmed.
  Future<void> uploadAnglePhoto({
    required String sessionId,
    required int angleId,
    required Uint8List photoBytes,
    required int photoIndex,
  }) async {
    final formData = FormData.fromMap({
      'sessionId': sessionId,
      'angleId': angleId,
      'photoIndex': photoIndex,
      'file': MultipartFile.fromBytes(
        photoBytes,
        filename: '${angleId}_$photoIndex.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });
    await _client.post<dynamic>(
      '/TODO_upload_endpoint',
      data: formData,
    );
  }

  /// TODO: replace path and response parsing once endpoint is confirmed.
  Future<dynamic> fetchResult({required String sessionId}) async {
    return _client.get<dynamic>(
      '/TODO_result_endpoint',
      queryParameters: {'sessionId': sessionId},
    );
  }
}
