import '../../../../core/cache/session_cache.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/repository/auth_repository.dart';
import '../datasource/auth_remote_datasource.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  Future<Result<String?, Failure>> fetchBaseUrlOnPremise() async {
    try {
      final baseUrlOnPremise = await _remote.getBaseUrlOnPremise();
      SessionCache.instance.baseUrlOnPremise = baseUrlOnPremise;
      return Success(baseUrlOnPremise);
    } catch (e) {
      return FailureResult(_mapError(e));
    }
  }

  Failure _mapError(Object e) {
    return switch (e) {
      NetworkException(:final message) =>
        NetworkFailure(message ?? 'No internet connection'),
      UnauthorizedException(:final message) =>
        UnauthorizedFailure(message ?? 'Unauthorized'),
      ServerException(:final message, :final statusCode) =>
        ServerFailure(message ?? 'Server error occurred', statusCode),
      _ => ServerFailure(e.toString()),
    };
  }
}
