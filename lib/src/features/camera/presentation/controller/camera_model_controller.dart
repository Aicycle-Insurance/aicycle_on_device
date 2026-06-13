import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../config/aicycle_config.dart';
import '../../../../core/cache/session_cache.dart';
import '../../../ai_model_manager/data/model/ai_model.dart';
import '../../../ai_model_manager/domain/entity/ai_model_type.dart';
import '../../../ai_model_manager/domain/repository/ai_model_repository.dart';
import '../../../aicycle_folder/domain/repository/aicycle_folder_repository.dart';

class CameraModelController extends ChangeNotifier {
  CameraModelController(this._modelRepository, this._folderRepository);

  final AiModelRepository _modelRepository;
  final AICycleFolderRepository _folderRepository;

  Map<AiModelType, String?> _initialPaths = {};
  AICycleConfig? _config;

  final Map<AiModelType, String> _modelPaths = {};

  bool _folderReady = false;
  String? _folderError;

  bool _isPreparing = true;
  String? _modelError;

  AiModelType? _downloadingType;
  double _downloadProgress = 0;

  void Function(String message)? onError;

  // ----- Public state -----

  bool get folderReady => _folderReady;
  String? get folderError => _folderError;

  bool get isPreparing => _isPreparing;
  String? get modelError => _modelError;

  bool get isReady =>
      _folderReady &&
      !_isPreparing &&
      _modelError == null &&
      AiModelType.values.every(_modelPaths.containsKey);

  AiModelType? get downloadingType => _downloadingType;
  double get downloadProgress => _downloadProgress;
  String? modelPathOf(AiModelType type) => _modelPaths[type];

  // ----- Init -----

  /// Bước khởi tạo duy nhất mà view gọi.
  /// Tự động bỏ qua tạo folder nếu claimId đã có trong SessionCache
  /// (trường hợp đến từ màn quản lý model).
  Future<void> init(
    AICycleConfig config,
    Map<AiModelType, String?> paths,
  ) async {
    _config = config;
    _initialPaths = paths;
    // TODO: remove this line and un-comment the folder creation block below when done testing UI flow
    _folderReady = true;
    await _prepareModels(paths);

    // if (SessionCache.instance.claimId != null) {
    //   _folderReady = true;
    //   notifyListeners();
    //   await _prepareModels(paths);
    //   return;
    // }
    // await _createFolder(paths);
  }

  Future<void> retryFolder() async {
    _folderError = null;
    notifyListeners();
    await _createFolder(_initialPaths);
  }

  Future<void> retryModels() => _prepareModels(_initialPaths);

  // ----- Private -----

  Future<void> _createFolder(Map<AiModelType, String?> paths) async {
    final config = _config!;
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
      (failure) {
        onError?.call(failure.message);
        _folderError = failure.message;
        _isPreparing = false;
        notifyListeners();
      },
      (_) async {
        _folderReady = true;
        notifyListeners();
        await _prepareModels(paths);
      },
    );
  }

  Future<void> _prepareModels(Map<AiModelType, String?> paths) async {
    _initialPaths = paths;
    _isPreparing = true;
    _modelError = null;
    notifyListeners();

    try {
      for (final type in AiModelType.values) {
        final provided = paths[type];
        if (provided != null && File(provided).existsSync()) {
          _modelPaths[type] = provided;
          continue;
        }
        _modelPaths[type] = await _ensureLatestModel(type);
      }
    } on _PrepareException catch (e) {
      _modelError = e.message;
      onError?.call(e.message);
    } finally {
      _isPreparing = false;
      _downloadingType = null;
      notifyListeners();
    }
  }

  Future<String> _ensureLatestModel(AiModelType type) async {
    final models = (await _modelRepository.getModels(type)).fold(
      (failure) => throw _PrepareException(failure.message),
      (models) => models,
    );
    if (models.isEmpty) {
      throw _PrepareException('No model available for ${type.apiValue}');
    }
    final latest = models.reduce(_newer);

    final manifest = (await _modelRepository.getLocalState()).fold(
      (failure) => throw _PrepareException(failure.message),
      (manifest) => manifest,
    );
    final existing =
        manifest.downloaded.where((e) => e.id == latest.id).firstOrNull;
    if (existing != null) {
      await _modelRepository.selectModel(latest);
      return existing.filePath;
    }

    _downloadingType = type;
    _downloadProgress = 0;
    notifyListeners();

    final info = (await _modelRepository.downloadModel(
      latest,
      onProgress: (progress) {
        if (progress - _downloadProgress >= 0.01) {
          _downloadProgress = progress;
          notifyListeners();
        }
      },
    ))
        .fold(
      (failure) => throw _PrepareException(failure.message),
      (info) => info,
    );

    _downloadingType = null;

    final oldVersions =
        manifest.downloaded.where((e) => e.type == type && e.id != latest.id);
    for (final old in oldVersions) {
      await _modelRepository.deleteModel(old.id);
    }

    await _modelRepository.selectModel(latest);
    return info.filePath;
  }

  AiModel _newer(AiModel a, AiModel b) {
    final cmp = _compareVersions(a.version, b.version);
    if (cmp != 0) return cmp > 0 ? a : b;
    return a.createdDate.isAfter(b.createdDate) ? a : b;
  }

  int _compareVersions(String a, String b) {
    final partsA = a.split('.');
    final partsB = b.split('.');
    final length =
        partsA.length > partsB.length ? partsA.length : partsB.length;
    for (var i = 0; i < length; i++) {
      final numA = i < partsA.length ? int.tryParse(partsA[i]) ?? 0 : 0;
      final numB = i < partsB.length ? int.tryParse(partsB[i]) ?? 0 : 0;
      if (numA != numB) return numA.compareTo(numB);
    }
    return 0;
  }
}

class _PrepareException implements Exception {
  const _PrepareException(this.message);
  final String message;
}
