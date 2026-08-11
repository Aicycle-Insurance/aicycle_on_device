import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../config/aicycle_config.dart';
import '../../../../core/cache/session_cache.dart';
import '../../../ai_model_manager/data/model/ai_model.dart';
import '../../../ai_model_manager/data/model/downloaded_model_info.dart';
import '../../../ai_model_manager/data/model/model_manifest.dart';
import '../../../ai_model_manager/domain/entity/ai_model_type.dart';
import '../../../ai_model_manager/domain/repository/ai_model_repository.dart';
import '../../../aicycle_folder/domain/repository/aicycle_folder_repository.dart';
import '../../../../yolo/core/yolo_model_resolver.dart';
import '../../../../yolo/models/yolo_task.dart';

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
  /// 1. Reuses a locally selected/downloaded model immediately when it has
  ///    already passed validation.
  /// 2. Uses a provided path when it is not part of the local manifest.
  /// 3. Only calls the model APIs for types that are genuinely missing locally.
  ///
  /// This keeps repeat camera opens off the network and avoids recompiling
  /// CoreML packages that were already validated by the model manager.
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
    _modelPaths.clear();
    notifyListeners();

    try {
      final manifest = (await _modelRepository.getLocalState()).fold(
        (failure) => throw _PrepareException(failure.message),
        (manifest) => manifest,
      );
      final remoteTypes = <AiModelType>[];
      final invalidLocalIds = <int>{};

      for (final type in AiModelType.values) {
        final provided = paths[type];
        if (provided != null && _pathExists(provided)) {
          final downloaded = manifest.downloaded
              .where((item) => item.type == type && item.filePath == provided)
              .firstOrNull;
          _modelPaths[type] = downloaded == null
              ? (await _validateModelPath(provided, type)).path
              : await _validPathOfDownloaded(downloaded, type);
          continue;
        }

        final local = _preferredLocalModel(manifest, type);
        if (local != null) {
          try {
            _modelPaths[type] = await _validPathOfDownloaded(local, type);
            continue;
          } on _PrepareException {
            invalidLocalIds.add(local.id);
            await _modelRepository.deleteModel(local.id);
          }
        }
        remoteTypes.add(type);
      }
      if (remoteTypes.isEmpty) return;

      final listResults = await Future.wait([
        for (final type in remoteTypes) _modelRepository.getModels(type),
      ]);
      final usableManifest = manifest.copyWith(
        downloaded: manifest.downloaded
            .where((item) => !invalidLocalIds.contains(item.id))
            .toList(),
      );

      for (var i = 0; i < remoteTypes.length; i++) {
        final type = remoteTypes[i];
        final models = listResults[i].fold(
          (failure) => throw _PrepareException(failure.message),
          (models) => models,
        );
        _modelPaths[type] =
            await _ensureLatestModel(type, models, usableManifest);
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

  /// Returns the explicitly selected local model, falling back to the newest
  /// downloaded model of [type] when an older manifest has no selection entry.
  DownloadedModelInfo? _preferredLocalModel(
    ModelManifest manifest,
    AiModelType type,
  ) {
    final selectedId = manifest.selected[type];
    final selected = manifest.downloaded
        .where((item) => item.type == type && item.id == selectedId)
        .firstOrNull;
    if (selected != null) return selected;

    final candidates =
        manifest.downloaded.where((item) => item.type == type).toList()
          ..sort((a, b) {
            final version = _compareVersions(b.version, a.version);
            if (version != 0) return version;
            return b.createdDate.compareTo(a.createdDate);
          });
    return candidates.firstOrNull;
  }

  bool _pathExists(String path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  /// Ensures the latest model of a given type is available locally.
  ///
  /// Process:
  /// 1. Finds the newest version (by version number, then by creation date)
  ///    among [models] fetched from the repository
  /// 2. Checks if this model is already downloaded (per [manifest])
  /// 3. If not, downloads it with progress tracking
  /// 4. Deletes older versions of the same type
  /// 5. Marks the latest model as selected
  ///
  /// Returns the file path to the model.
  ///
  /// Throws _PrepareException if any step fails.
  ///
  /// Parameters:
  ///   - type: The AI model type to ensure
  ///   - models: Available models of this type, already fetched from server
  ///   - manifest: Local state, already read from disk
  Future<String> _ensureLatestModel(
    AiModelType type,
    List<AiModel> models,
    ModelManifest manifest,
  ) async {
    if (models.isEmpty) {
      throw _PrepareException('No model available for ${type.apiValue}');
    }
    final latest = models.reduce(_newer);

    final existing =
        manifest.downloaded.where((e) => e.id == latest.id).firstOrNull;
    if (existing != null) {
      try {
        final validPath = await _validPathOfDownloaded(existing, type);
        await _modelRepository.selectModel(latest);
        return validPath;
      } on _PrepareException {
        await _modelRepository.deleteModel(existing.id);
      }
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
    late final String preparedPath;
    try {
      preparedPath = await _prepareManagedModelPath(info, type);
    } on _PrepareException {
      await _modelRepository.deleteModel(info.id);
      rethrow;
    }

    final oldVersions =
        manifest.downloaded.where((e) => e.type == type && e.id != latest.id);
    for (final old in oldVersions) {
      await _modelRepository.deleteModel(old.id);
    }

    await _modelRepository.selectModel(latest);
    return preparedPath;
  }

  /// Returns a valid path for an already-downloaded model.
  ///
  /// Server-managed models already carry their type in the API/manifest. Path
  /// preparation verifies that the downloaded archive/package is readable; we
  /// then record the trusted task and avoid a separate native inspect pass.
  /// On iOS that inspect would compile CoreML once here and then compile/load it
  /// again when the camera view starts, dominating the preparing-screen time.
  /// External paths that are not in the manifest still use [_validateModelPath].
  Future<String> _validPathOfDownloaded(
    DownloadedModelInfo info,
    AiModelType type,
  ) async {
    final cachedTask = info.validatedTask;
    if (cachedTask == null) {
      return _prepareManagedModelPath(info, type);
    }

    try {
      final preparedPath = await YOLOModelResolver.preparePath(info.filePath);
      if (FileSystemEntity.typeSync(preparedPath) ==
          FileSystemEntityType.notFound) {
        throw _PrepareException('${type.apiValue} model file is missing.');
      }
      _ensureTaskMatches(type, cachedTask);
      return preparedPath;
    } on _PrepareException {
      rethrow;
    } catch (e) {
      throw _PrepareException(
        '${type.apiValue} model is invalid or corrupted: $e',
      );
    }
  }

  Future<String> _prepareManagedModelPath(
    DownloadedModelInfo info,
    AiModelType type,
  ) async {
    try {
      final preparedPath = await YOLOModelResolver.preparePath(info.filePath);
      if (FileSystemEntity.typeSync(preparedPath) ==
          FileSystemEntityType.notFound) {
        throw _PrepareException('${type.apiValue} model file is missing.');
      }
      final trustedTask = _expectedYoloTask(type)?.name ?? '';
      await _modelRepository.markModelValidated(info.id, trustedTask);
      return preparedPath;
    } on _PrepareException {
      rethrow;
    } catch (e) {
      throw _PrepareException(
        '${type.apiValue} model is invalid or corrupted: $e',
      );
    }
  }

  /// Fully validates a model: resolves the path, inspects the model natively
  /// (expensive — compiles the CoreML model on iOS) and checks its task.
  ///
  /// Returns the prepared path together with the metadata task string so
  /// callers can record it as the validation cache.
  Future<({String path, String? task})> _validateModelPath(
    String path,
    AiModelType type,
  ) async {
    try {
      final preparedPath = await YOLOModelResolver.preparePath(path);
      final metadata = await YOLOModelResolver.inspect(preparedPath);
      final task = metadata['task'] as String?;
      _ensureTaskMatches(type, task);
      return (path: preparedPath, task: task);
    } on _PrepareException {
      rethrow;
    } catch (e) {
      throw _PrepareException(
        '${type.apiValue} model is invalid or corrupted: $e',
      );
    }
  }

  /// Throws _PrepareException if [taskString] conflicts with the task
  /// expected for [type]. Unknown/empty tasks pass (e.g. OCR models).
  void _ensureTaskMatches(AiModelType type, String? taskString) {
    final expectedTask = _expectedYoloTask(type);
    final actualTask = YOLOTaskParsing.tryParse(taskString);
    if (expectedTask != null &&
        actualTask != null &&
        actualTask != expectedTask) {
      throw _PrepareException(
        '${type.apiValue} model task mismatch: expected '
        '${expectedTask.name}, metadata says ${actualTask.name}.',
      );
    }
  }

  YOLOTask? _expectedYoloTask(AiModelType type) {
    return switch (type) {
      AiModelType.carCorner => YOLOTask.classify,
      AiModelType.carDamage => YOLOTask.detect,
      AiModelType.carPart => YOLOTask.detect,
      // LicensePlate is a standalone OCR CoreML model, not a YOLO task.
      AiModelType.licensePlate => null,
    };
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
