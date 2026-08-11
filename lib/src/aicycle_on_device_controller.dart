import 'package:flutter/foundation.dart';

import 'config/aicycle_config.dart';
import 'core/cache/session_cache.dart';
import 'features/aicycle_folder/domain/repository/aicycle_folder_repository.dart';

class AICycleOnDeviceController extends ChangeNotifier {
  AICycleOnDeviceController(this._folderRepository);

  final AICycleFolderRepository _folderRepository;

  bool _isLoading = true;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isReady => !_isLoading && _error == null;

  Future<void> init(AICycleConfig config) async {
    SessionCache.instance.clear();
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Khởi tạo hồ sơ (claim folder).
    final car = config.carInformation;
    final result = await _folderRepository.createAICycleFolder(
      externalClaimId: config.generalConfig.documentId,
      claimName: config.generalConfig.documentName,
      vehicleBrandId: car.vehicleBrandId,
      brand: car.companyName,
      model: car.modelName,
      vehicleYear: car.manufacturingYear,
      vehicleSpec: car.vehicleVersionName,
      licensePlate: car.licensePlate,
      vehicleType: car.vehicleType,
      isClaim: true,
      hasLicensePlate: car.licensePlate.isNotEmpty,
      priceTypeId: int.tryParse(car.garageId),
    );

    result.fold(
      (failure) => _error = failure.message,
      (_) => null,
    );
    _isLoading = false;
    notifyListeners();
  }

  Future<void> retry(AICycleConfig config) => init(config);
}
