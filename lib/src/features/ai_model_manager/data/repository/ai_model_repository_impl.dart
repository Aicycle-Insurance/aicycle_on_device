import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/result.dart';
import '../../domain/entity/ai_model_type.dart';
import '../../domain/repository/ai_model_repository.dart';
import '../datasource/ai_model_local_datasource.dart';
import '../datasource/ai_model_remote_datasource.dart';
import '../model/ai_model.dart';
import '../model/downloaded_model_info.dart';
import '../model/model_manifest.dart';

class AiModelRepositoryImpl implements AiModelRepository {
  AiModelRepositoryImpl(this._remote, this._local);

  final AiModelRemoteDataSource _remote;
  final AiModelLocalDataSource _local;

  @override
  Future<Result<List<AiModel>, Failure>> getModels(AiModelType type) async {
    try {
      return Success(await _remote.getModels(type));
    } catch (e) {
      return FailureResult(_mapError(e));
    }
  }

  @override
  Future<Result<ModelManifest, Failure>> getLocalState() async {
    try {
      return Success(await _local.readManifest());
    } catch (e) {
      return FailureResult(_mapError(e));
    }
  }

  @override
  Future<int?> getModelFileSize(AiModel model) {
    return _remote.getFileSize(model.modelDownloadUrl);
  }

  @override
  Future<Result<DownloadedModelInfo, Failure>> downloadModel(
    AiModel model, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final tempPath = await _local.createTempFilePath(model);
      await _remote.downloadFile(
        model.modelDownloadUrl,
        tempPath,
        onProgress: onProgress,
      );
      return Success(await _local.persistDownloadedModel(model, tempPath));
    } catch (e) {
      return FailureResult(_mapError(e));
    }
  }

  @override
  Future<Result<ModelManifest, Failure>> deleteModel(int modelId) async {
    try {
      return Success(await _local.deleteModel(modelId));
    } catch (e) {
      return FailureResult(_mapError(e));
    }
  }

  @override
  Future<Result<void, Failure>> deleteAllModels() async {
    try {
      await _local.deleteAllModels();
      return const Success(null);
    } catch (e) {
      return FailureResult(_mapError(e));
    }
  }

  @override
  Future<Result<void, Failure>> selectModel(AiModel model) async {
    try {
      await _local.setSelectedModel(model.type, model.id);
      return const Success(null);
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
      CacheException(:final message) =>
        CacheFailure(message ?? 'Cache error occurred'),
      ServerException(:final message, :final statusCode) =>
        ServerFailure(message ?? 'Server error occurred', statusCode),
      _ => ServerFailure(e.toString()),
    };
  }
}
