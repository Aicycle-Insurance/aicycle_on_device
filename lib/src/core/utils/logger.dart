import 'dart:developer' as developer;

import '../../config/config_holder.dart';

class LoggerService {
  void d(String message) {
    _log('DEBUG', message);
  }

  void i(String message) {
    _log('INFO', message);
  }

  void w(String message) {
    _log('WARNING', message);
  }

  void e(String message, [dynamic error, StackTrace? stackTrace]) {
    _log('ERROR', message, error, stackTrace);
  }

  void _log(
    String level,
    String message, [
    dynamic error,
    StackTrace? stackTrace,
  ]) {
    try {
      if (AICycleConfigHolder.isInitialized &&
          AICycleConfigHolder.config.generalConfig.loggingEnabled) {
        developer.log(
          message,
          name: 'AiCycle',
          level: _getLevelValue(level),
          error: error,
          stackTrace: stackTrace,
          time: DateTime.now(),
        );
      }
    } catch (_) {
      // Fallback or ignore if config is not yet initialized
    }
  }

  int _getLevelValue(String level) {
    switch (level) {
      case 'DEBUG':
        return 500;
      case 'INFO':
        return 800;
      case 'WARNING':
        return 900;
      case 'ERROR':
        return 1000;
      default:
        return 0;
    }
  }
}
