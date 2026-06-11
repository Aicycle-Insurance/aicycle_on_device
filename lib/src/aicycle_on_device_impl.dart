import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../aicycle_on_device.dart';
import 'features/ai_model_manager/presentation/model_manager_screen.dart';

class AICycleOnDevice extends StatefulWidget {
  const AICycleOnDevice({
    super.key,
    required this.aiCycleConfig,
    this.onError,
    this.onComplete,
  });

  /// Cấu hình SDK
  final AICycleConfig aiCycleConfig;

  /// Callback when initialization fails
  final Function(String error)? onError;

  /// Callback when initialization succeeds.
  /// If provided, the widget will not automatically navigate to the default flow.
  final Function(dynamic data)? onComplete;

  static AICycleConfig? configInternal;

  /// Get the current configuration. Throws if not initialized.
  static AICycleConfig get config {
    if (configInternal == null) {
      throw StateError(
        'AICycleOnDevice has not been initialized. Ensure AICycleOnDevice widget is in the tree.',
      );
    }
    return configInternal!;
  }

  @override
  State<AICycleOnDevice> createState() => _AICycleOnDeviceState();
}

class _AICycleOnDeviceState extends State<AICycleOnDevice> {
  @override
  void initState() {
    super.initState();
    // Make config available to DioClient/LoggerService via AICycleOnDevice.config
    AICycleOnDevice.configInternal = widget.aiCycleConfig;
    // Lock orientation to portrait when using the package
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  Widget build(BuildContext context) {
    return ModelManagerScreen(
      showBackButton: widget.aiCycleConfig.displayConfig.showBackButton,
      onContinue: (selectedModels) {
        // TODO: Điều hướng sang màn camera khi màn đó được xây dựng.
        widget.onComplete?.call(selectedModels);
      },
    );
  }
}
