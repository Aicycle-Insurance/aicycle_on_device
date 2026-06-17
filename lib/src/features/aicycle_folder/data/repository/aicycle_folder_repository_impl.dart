import '../../../../../aicycle_on_device.dart';
import '../../../../config/config_holder.dart';
import '../../../../core/cache/session_cache.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/repository/aicycle_folder_repository.dart';
import '../datasource/aicycle_folder_remote_datasource.dart';

class AICycleFolderRepositoryImpl implements AICycleFolderRepository {
  AICycleFolderRepositoryImpl(this._remote);

  final AICycleFolderRemoteDataSource _remote;

  @override
  Future<Result<String, Failure>> createAICycleFolder({
    required String externalClaimId,
    String? claimName,
    String? vehicleBrandId,
    int? priceTypeId,
    bool? isClaim,
    String? brand,
    String? model,
    int? vehicleYear,
    String? vehicleSpec,
    String? licensePlate,
    String? vehicleType,
    bool? hasLicensePlate,
  }) async {
    /// Nếu là AICycle -> externalClaimId là claimId
    if (AICycleConfigHolder.config.generalConfig.organization ==
        AiCycleOrg.aicycle) {
      final folder = await _remote.getClaimFolderById(externalClaimId);
      return _cacheAndReturn(folder.claimId?.toString() ?? '');
    }

    final data = {
      'externalClaimId': externalClaimId,
      'claimName': claimName,
      if (vehicleBrandId != null && vehicleBrandId.isNotEmpty)
        'vehicleBrandId': vehicleBrandId,
      if (priceTypeId != null) 'priceTypeId': priceTypeId,
      'isClaim': isClaim,
      'brand': brand,
      'model': model,
      'vehicleYear': vehicleYear,
      'vehicleSpec': vehicleSpec,
      'vehicleLicensePlates': licensePlate,
      'vehicleType': vehicleType,
      'hasLicensePlate': hasLicensePlate,
    };

    try {
      final folder = await _remote.createAICycleFolder(data);
      return _cacheAndReturn(folder.claimId?.toString() ?? '');
    } catch (e) {
      if (e.toString().toLowerCase().contains('duplicate')) {
        try {
          final folder = await _remote.getDuplicateFolder(externalClaimId);
          return _cacheAndReturn(folder.claimId?.toString() ?? '');
        } catch (inner) {
          return FailureResult(_mapError(inner));
        }
      }
      return FailureResult(_mapError(e));
    }
  }

  Success<String, Failure> _cacheAndReturn(String claimId) {
    SessionCache.instance.claimId = claimId;
    return Success(claimId);
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
