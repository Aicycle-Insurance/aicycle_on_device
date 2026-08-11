import 'aicycle_config.dart';

/// Internal extension to provide base URLs based on environment.
/// This prevents end-users from seeing these URLs in their IDE autocomplete.
extension AiCycleConfigInternal on AICycleConfig {
  /// Ưu tiên dùng [GeneralConfig.aicBaseUrl] nếu được cung cấp,
  /// nếu null thì fallback về URL theo môi trường.
  String get baseUrl {
    final aicBaseUrl = generalConfig.aicBaseUrl;
    if (aicBaseUrl != null && aicBaseUrl.isNotEmpty) {
      return aicBaseUrl;
    }
    switch (generalConfig.environment) {
      case AiCycleEnvironment.develop:
        return 'https://dev.api.aicycle.ai';
      case AiCycleEnvironment.stage:
        return 'https://stage.api.aicycle.ai';
      case AiCycleEnvironment.production:
        return 'https://prod.api.aicycle.ai';
    }
  }

  String get adminBaseUrl {
    switch (generalConfig.environment) {
      case AiCycleEnvironment.develop:
        return 'https://dev.api.aicycle.ai/admin';
      case AiCycleEnvironment.stage:
        return 'https://stage.api.aicycle.ai/admin';
      case AiCycleEnvironment.production:
        return 'https://prod.api.aicycle.ai/admin';
    }
  }
}
