import '../../../../core/network/dio_client.dart';
import '../model/aicycle_folder_model.dart';

class AICycleFolderRemoteDataSource {
  AICycleFolderRemoteDataSource(this._client);

  final DioClient _client;

  /// POST /claimfolders
  Future<AICycleFolderModel> createAICycleFolder(
    Map<String, dynamic> data,
  ) async {
    final response = await _client.post<dynamic>(
      '/insurance/claimfolders',
      data: data,
    );
    return AICycleFolderModel.fromDynamic(response);
  }

  /// GET /claimfolders?externalClaimId=...
  Future<AICycleFolderModel> getDuplicateFolder(String externalId) async {
    final response = await _client.get<dynamic>(
      '/insurance/claimfolders',
      queryParameters: {'externalClaimId': externalId},
    );
    return AICycleFolderModel.fromDynamic(response);
  }

  /// GET /claimfolders/{claimId}
  Future<AICycleFolderModel> getClaimFolderById(String claimId) async {
    final response =
        await _client.get<dynamic>('/insurance/claimfolders/$claimId');
    return AICycleFolderModel.fromDynamic(response);
  }
}
