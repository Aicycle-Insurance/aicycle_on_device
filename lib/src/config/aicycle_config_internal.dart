import 'aicycle_config.dart';

/// Internal extension to provide base URLs based on environment.
/// This prevents end-users from seeing these URLs in their IDE autocomplete.
extension AiCycleConfigInternal on AICycleConfig {
  String get baseUrl {
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
