import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../aicycle_on_device.dart';
import 'config/config_holder.dart';
import 'features/ai_model_manager/presentation/model_manager_screen.dart';
import 'features/camera/presentation/camera_view.dart';

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

  @override
  State<AICycleOnDevice> createState() => _AICycleOnDeviceState();
}

class _AICycleOnDeviceState extends State<AICycleOnDevice> {
  @override
  void initState() {
    super.initState();
    // Make config available package-wide (DioClient, LoggerService, camera, ...)
    AICycleConfigHolder.init(widget.aiCycleConfig);
    // Lock orientation to portrait when using the package
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  Widget build(BuildContext context) {
    return ModelManagerScreen(
      showBackButton: widget.aiCycleConfig.displayConfig.showBackButton,
      onContinue: (selectedModels) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AICycleOnDeviceCamera(
              aiCycleConfig: widget.aiCycleConfig,
              onError: widget.onError,
              onComplete: widget.onComplete,
              carCornerModelPath:
                  selectedModels[AiModelType.carCorner]?.filePath,
              carDamageModelPath:
                  selectedModels[AiModelType.carDamage]?.filePath,
              carPartModelPath: selectedModels[AiModelType.carPart]?.filePath,
            ),
          ),
        );
      },
    );
  }
}
