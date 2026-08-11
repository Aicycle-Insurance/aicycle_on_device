import '../../../../core/error/failures.dart';
import '../../../../core/utils/result.dart';

abstract class AICycleFolderRepository {
  /// Tạo folder mới. Nếu server trả duplicate error, tự động lấy folder đã tồn tại.
  /// Trả về claimId dạng String khi thành công.
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
  });
}
