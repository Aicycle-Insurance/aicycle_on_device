import 'aicycle_config.dart';

/// Internal extension to provide base URLs based on environment.
/// This prevents end-users from seeing these URLs in their IDE autocomplete.
extension AiCycleConfigInternal on AICycleConfig {
  String get baseUrl {
    switch (generalConfig.environment) {
      case AiCycleEnvironment.develop:
        return 'https://dev.api.aicycle.ai/insurance';
      case AiCycleEnvironment.stage:
        return 'https://stage.api.aicycle.ai/insurance';
      case AiCycleEnvironment.production:
        return 'https://api-aws-insurance.aicycle.ai';
    }
  }

  String get adminBaseUrl {
    switch (generalConfig.environment) {
      case AiCycleEnvironment.develop:
        return 'https://dev.api.aicycle.ai/admin';
      case AiCycleEnvironment.stage:
        return 'https://stage.api.aicycle.ai/admin';
      case AiCycleEnvironment.production:
        return 'https://api-aws-admin.aicycle.ai';
    }
  }
}