import '../../../../config/aicycle_config_internal.dart';
import '../../../../config/config_holder.dart';
import '../../../../core/network/dio_client.dart';

class AuthRemoteDataSource {
  AuthRemoteDataSource(this._client);

  final DioClient _client;

  /// GET {adminBaseUrl}/bearer
  ///
  /// Lấy `userInfo.organizations.kvp.claimBuyMe.baseUrlOnPremise` từ thông tin user tương ứng
  /// với apiToken (đã được DioClient tự gắn vào header Authorization).
  Future<String?> getBaseUrlOnPremise() async {
    final response = await _client.get<dynamic>(
      '/bearer',
      customBaseUrl: AICycleConfigHolder.config.adminBaseUrl,
    );

    final json = response is Map<String, dynamic> &&
            response.containsKey('data') &&
            response['data'] is Map<String, dynamic>
        ? response['data'] as Map<String, dynamic>
        : response;

    if (json is! Map<String, dynamic>) return null;
    final userInfo = json['userInfo'];
    if (userInfo is! Map<String, dynamic>) return null;
    final orgs = userInfo['organizations'];
    if (orgs is! List || orgs.isEmpty) return null;
    final currentOrg = orgs.first;
    if (currentOrg is! Map<String, dynamic>) return null;
    final kvp = currentOrg['kvp'];
    if (kvp is! Map<String, dynamic>) return null;
    final claimBuyMe = kvp['claimBuyMe'];
    if (claimBuyMe is! Map<String, dynamic>) return null;
    return claimBuyMe['baseUrlOnPremise']?.toString();
  }
}
