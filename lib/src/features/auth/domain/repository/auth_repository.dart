import '../../../../core/error/failures.dart';
import '../../../../core/utils/result.dart';

abstract class AuthRepository {
  /// Gọi `/bearer`, lưu `kvp.claimBuyMe.baseUrlOnPremise` vào
  /// `SessionCache.instance` và trả về giá trị đó.
  Future<Result<String?, Failure>> fetchBaseUrlOnPremise();
}
