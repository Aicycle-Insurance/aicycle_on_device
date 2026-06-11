import '../network/dio_client.dart';
import '../utils/logger.dart';

class AICycleInjection {
  AICycleInjection._();

  static final AICycleInjection _instance = AICycleInjection._();
  factory AICycleInjection() => _instance;

  // --- Core ---
  late final LoggerService logger = LoggerService();
  late final DioClient _dioClient = DioClient(logger);
}

/// Global instance for accessing dependencies.
final sl = AICycleInjection();
