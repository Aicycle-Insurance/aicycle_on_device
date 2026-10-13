import '../../../../../aicycle_on_device.dart';
import '../../../../config/config_holder.dart';
import '../../../../core/network/dio_client.dart';
import '../model/result_model.dart';

class ResultRemoteDataSource {
  ResultRemoteDataSource(this._client);

  final DioClient _client;

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
