import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../config/aicycle_config.dart';
import '../../../../core/cache/session_cache.dart';
import '../../../ai_model_manager/data/model/ai_model.dart';
import '../../../ai_model_manager/domain/entity/ai_model_type.dart';
import '../../../ai_model_manager/domain/repository/ai_model_repository.dart';
import '../../../aicycle_folder/domain/repository/aicycle_folder_repository.dart';

class CameraModelController extends ChangeNotifier {
  CameraModelController(
    this._modelRepository,
    this._folderRepository,
  );

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

  /// Initializes the controller with configuration and model paths.
  ///
  /// This is the single initialization step that the view calls.
  /// Automatically skips folder creation if claimId is already in SessionCache
  /// (case of coming from model management screen).
  ///
  /// Parameters:
  ///   - config: The AICycle configuration containing car information and document details
  ///   - paths: Map of model types to their optional file paths (for pre-provided models)
  Future<void> init(
    AICycleConfig config,
    Map<AiModelType, String?> paths,
  ) async {
    _config = config;
    _initialPaths = paths;

    if (SessionCache.instance.claimId != null) {
      _folderReady = true;
      notifyListeners();
      await _prepareModels(paths);
      return;
    }
    await _createFolder(paths);
  }

  /// Retries folder creation after a previous failure.
  ///
  /// Clears the folder error state and attempts to create the AICycle folder again
  /// with the initial paths.
  Future<void> retryFolder() async {
    _folderError = null;
    notifyListeners();
    await _createFolder(_initialPaths);
  }

  /// Retries model preparation after a previous failure.
  ///
  /// Attempts to prepare all models again with the initial paths.
  Future<void> retryModels() => _prepareModels(_initialPaths);

  // ----- Private -----

  /// Creates a new AICycle folder with vehicle and claim information.
  ///
  /// Extracts vehicle details from the config and calls the folder repository
  /// to create a new folder. On success, proceeds with model preparation.
  /// On failure, sets the folder error and notifies listeners.
  ///
  /// Parameters:
  ///   - paths: Map of model types to their optional file paths
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

  /// Prepares all AI models for use.
  ///
  /// For each model type:
  /// 1. Uses provided path if file exists
  /// 2. Otherwise, ensures the latest model is available (downloading if needed)
  ///
  /// Sets isPreparing to true during the process and catches any errors.
  /// Notifies listeners of completion.
  ///
  /// Parameters:
  ///   - paths: Map of model types to their optional file paths
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

  /// Ensures the latest model of a given type is available locally.
  ///
  /// Process:
  /// 1. Fetches all available models of the type from the repository
  /// 2. Finds the newest version (by version number, then by creation date)
  /// 3. Checks if this model is already downloaded
  /// 4. If not, downloads it with progress tracking
  /// 5. Deletes older versions of the same type
  /// 6. Marks the latest model as selected
  ///
  /// Returns the file path to the model.
  ///
  /// Throws _PrepareException if any step fails.
  ///
  /// Parameters:
  ///   - type: The AI model type to ensure
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

  /// Compares two AI models and returns the newer one.
  ///
  /// First compares by version number (semantic versioning).
  /// If versions are equal, compares by creation date (newer is better).
  ///
  /// Parameters:
  ///   - a: First model to compare
  ///   - b: Second model to compare
  ///
  /// Returns the newer model (a or b).
  AiModel _newer(AiModel a, AiModel b) {
    final cmp = _compareVersions(a.version, b.version);
    if (cmp != 0) return cmp > 0 ? a : b;
    return a.createdDate.isAfter(b.createdDate) ? a : b;
  }

  /// Compares two semantic version strings (e.g., "1.2.3" vs "1.2.4").
  ///
  /// Handles variable-length versions by treating missing parts as 0.
  /// Compares each part numerically from left to right.
  ///
  /// Returns:
  ///   - Positive integer if a > b
  ///   - Negative integer if a < b
  ///   - 0 if a == b
  ///
  /// Parameters:
  ///   - a: First version string to compare
  ///   - b: Second version string to compare
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
