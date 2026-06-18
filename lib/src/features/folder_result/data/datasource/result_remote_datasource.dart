import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../../aicycle_on_device.dart';
import '../../../../config/config_holder.dart';
import '../../../../core/cache/session_cache.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/location_services.dart';
import '../model/result_model.dart';

class ResultRemoteDataSource {
  ResultRemoteDataSource(this._client);

  final DioClient _client;

  /// Base URL của server VBI (độc lập với hệ thống AICycle).
  static const _vbiBaseUrl = 'https://uat-api-mobile.evbi.vn/api/v1/vbi4sales';

  /// Upload to AICycle server
  /// POST /v2/claim-me/upload
  Future<void> uploadAnglePhoto({
    required int angleId,
    required Uint8List photoBytes,
    required int photoIndex,
  }) async {
    final config = AICycleConfigHolder.config;
    final sessionId = config.generalConfig.documentId;
    final formData = FormData.fromMap({
      if (config.generalConfig.organization == AiCycleOrg.aicycle)
        'claimFolderId': sessionId,
      if (config.generalConfig.organization != AiCycleOrg.aicycle)
        'externalSessionId': sessionId,
      'img': MultipartFile.fromBytes(
        photoBytes,
        filename: '${angleId}_$photoIndex.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });
    await _client.post<dynamic>(
      '/insurance/v2/claim-me/upload',
      customBaseUrl: SessionCache.instance.baseUrlOnPremise,
      data: formData,
    );

    /// Upload to VBI server
    if (config.generalConfig.organization == AiCycleOrg.vbi) {
      await _uploadToVBIServer(
        angleId: angleId,
        photoBytes: photoBytes,
        photoIndex: photoIndex,
      );
    }
  }

  /// Upload to VBI server
  /// POST {_vbiBaseUrl}/Upload/upload-ai
  Future<void> _uploadToVBIServer({
    required int angleId,
    required Uint8List photoBytes,
    required int photoIndex,
  }) async {
    final config = AICycleConfigHolder.config;
    final vbi = config.vbiConfig;
    if (vbi == null) return;

    double? latitude;
    double? longitude;
    final positionResult = await LocationService().getCurrentPosition();
    positionResult.fold(
      (_) {
        // Không lấy được vị trí — vẫn upload, bỏ qua latitude/longitude.
      },
      (position) {
        latitude = position.latitude;
        longitude = position.longitude;
      },
    );

    final formData = FormData.fromMap({
      'ExternalSessionId': vbi.externalSessionId,
      'Image': MultipartFile.fromBytes(
        photoBytes,
        filename: '${angleId}_$photoIndex.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
      'jobId': vbi.jobId,
      'ma_hang_muc': vbi.maHangMuc,
      'so_id_hs': config.generalConfig.documentId,
      'ten_hang_muc': vbi.tenHangMuc,
      'departmentId': vbi.departmentId,
      'user': vbi.userId,
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
      'ma_tvv': vbi.maTVV,
      'source': vbi.source,
    });

    await _client.post<dynamic>(
      '/Upload/upload-ai',
      customBaseUrl: _vbiBaseUrl,
      skipDefaultAuth: true,
      headers: {
        'Authority': vbi.authorityId,
        'Signature': vbi.signatureKey,
        'Accept': 'application/json',
      },
      data: formData,
    );
  }

  /// GET insurance/v2/claimfolders/$sessionId/external-segment-result
  Future<List<VehiclePartModel>> fetchResult() async {
    final config = AICycleConfigHolder.config;
    final sessionId = config.generalConfig.documentId;
    final endPoint = config.generalConfig.organization == AiCycleOrg.aicycle
        ? '/insurance/v2/claimfolders/$sessionId/segment-classify-result'
        : '/insurance/v2/claimfolders/$sessionId/external-segment-result';
    final list = await _client.get<List<dynamic>>(endPoint);
    return list
        .whereType<Map<String, dynamic>>()
        .map(VehiclePartModel.fromJson)
        .toList();
  }
}
