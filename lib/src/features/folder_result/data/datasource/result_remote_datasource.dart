import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../../../aicycle_on_device.dart';
import '../../../../config/config_holder.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/utils/location_services.dart';
import '../model/result_model.dart';

class ResultRemoteDataSource {
  ResultRemoteDataSource(this._client);

  final DioClient _client;

  /// Upload to AICycle server
  /// POST /v2/claim-me/upload
  ///
  /// Trả về body JSON server phản hồi cho ảnh vừa upload (null nếu không phải
  /// dạng map) để host nhận qua callback.
  Future<Map<String, dynamic>?> uploadAnglePhoto({
    required int angleId,
    required Uint8List photoBytes,
    required int photoIndex,
  }) async {
    final config = AICycleConfigHolder.config;
    final sessionId = config.generalConfig.documentId;

    /// Upload to VBI server
    if (config.generalConfig.organization == AiCycleOrg.vbi) {
      return _uploadToVBIServer(
        angleId: angleId,
        photoBytes: photoBytes,
        photoIndex: photoIndex,
      );
    } else {
      // Upload to AICycle server
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
      final res = await _client.post<dynamic>(
        '/insurance/v2/claim-me/upload',
        data: formData,
      );
      return _asJsonMap(res);
    }
  }

  /// Upload to VBI server
  /// POST {_vbiBaseUrl}/Upload/upload-ai
  Future<Map<String, dynamic>?> _uploadToVBIServer({
    required int angleId,
    required Uint8List photoBytes,
    required int photoIndex,
  }) async {
    final config = AICycleConfigHolder.config;
    final vbi = config.vbiConfig;
    if (vbi == null) return null;

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

    /// Chắc chắn != null do org VBI bắt buộc khai báo
    final versionCode = config.vbiConfig!.apiVersionCode;
    final res = await _client.post<dynamic>(
      '/api/$versionCode/vbi4sales/Upload/upload-ai',
      skipDefaultAuth: true,
      customBaseUrl: config.vbiConfig!.apiUploadBaseUrl,
      headers: {
        'Authority': vbi.authorityId,
        'Signature': vbi.signatureKey,
        'Accept': 'application/json',
      },
      data: formData,
    );
    return _asJsonMap(res);
  }

  /// Chuẩn hoá body phản hồi về [Map] JSON; null nếu không phải dạng map.
  Map<String, dynamic>? _asJsonMap(dynamic res) {
    if (res is Map<String, dynamic>) return res;
    if (res is Map) return Map<String, dynamic>.from(res);
    return null;
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
