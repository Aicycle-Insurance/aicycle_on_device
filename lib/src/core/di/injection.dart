import '../../features/ai_model_manager/data/datasource/ai_model_local_datasource.dart';
import '../../features/ai_model_manager/data/datasource/ai_model_remote_datasource.dart';
import '../../features/ai_model_manager/data/repository/ai_model_repository_impl.dart';
import '../../features/ai_model_manager/domain/repository/ai_model_repository.dart';
import '../../features/aicycle_folder/data/datasource/aicycle_folder_remote_datasource.dart';
import '../../features/aicycle_folder/data/repository/aicycle_folder_repository_impl.dart';
import '../../features/aicycle_folder/domain/repository/aicycle_folder_repository.dart';
import '../network/dio_client.dart';
import '../utils/logger.dart';

class AICycleInjection {
  AICycleInjection._();

  static final AICycleInjection _instance = AICycleInjection._();
  factory AICycleInjection() => _instance;

  // --- Core ---
  late final LoggerService logger = LoggerService();
  late final DioClient dioClient = DioClient(logger);

  // --- Feature: AI Model Manager ---
  late final AiModelRemoteDataSource _aiModelRemoteDataSource =
      AiModelRemoteDataSource(dioClient);
  late final AiModelLocalDataSource _aiModelLocalDataSource =
      AiModelLocalDataSource();
  late final AiModelRepository aiModelRepository = AiModelRepositoryImpl(
    _aiModelRemoteDataSource,
    _aiModelLocalDataSource,
  );

  // --- Feature: AICycle Folder ---
  late final AICycleFolderRemoteDataSource _aicycleFolderRemoteDataSource =
      AICycleFolderRemoteDataSource(dioClient);
  late final AICycleFolderRepository aicycleFolderRepository =
      AICycleFolderRepositoryImpl(_aicycleFolderRemoteDataSource);
}

/// Global instance for accessing dependencies.
final sl = AICycleInjection();
