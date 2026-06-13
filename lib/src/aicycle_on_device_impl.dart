import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../aicycle_on_device.dart';
import 'aicycle_on_device_controller.dart';
import 'config/config_holder.dart';
import 'core/constants/string_sheet.dart';
import 'core/di/injection.dart';
import 'core/themes/app_colors.dart';
import 'core/themes/app_textstyle.dart';
import 'core/utils/screen_utils.dart';
import 'features/ai_model_manager/presentation/model_manager_screen.dart';

class AICycleOnDevice extends StatefulWidget {
  const AICycleOnDevice({
    super.key,
    required this.aiCycleConfig,
    this.onError,
    this.onComplete,
  });

  final AICycleConfig aiCycleConfig;
  final Function(String error)? onError;
  final Function(dynamic data)? onComplete;

  @override
  State<AICycleOnDevice> createState() => _AICycleOnDeviceState();
}

class _AICycleOnDeviceState extends State<AICycleOnDevice> {
  late final AICycleOnDeviceController _controller;

  @override
  void initState() {
    super.initState();
    AICycleConfigHolder.init(widget.aiCycleConfig);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller = AICycleOnDeviceController(sl.aicycleFolderRepository);
    _controller.init(widget.aiCycleConfig).then((_) {
      if (_controller.error != null) {
        widget.onError?.call(_controller.error!);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ScreenUtil.init(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isLoading) return _buildLoading();
        if (_controller.error != null) return _buildError(_controller.error!);
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
                  carPartModelPath:
                      selectedModels[AiModelType.carPart]?.filePath,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLoading() {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primaryA500,
              backgroundColor: AppColors.primaryA200,
            ),
            16.verticalSpace,
            Text(
              StringSheet.creatingFolder,
              style: AppTextStyles.base.s14.ink400Color,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 40.w, color: AppColors.redA400),
              12.verticalSpace,
              Text(
                message,
                style: AppTextStyles.base.s14.ink400Color,
                textAlign: TextAlign.center,
              ),
              16.verticalSpace,
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      StringSheet.cancel,
                      style: AppTextStyles.base.s14.w600(),
                    ),
                  ),
                  12.horizontalSpace,
                  FilledButton(
                    onPressed: () => _controller.retry(widget.aiCycleConfig),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryA500,
                    ),
                    child: Text(
                      StringSheet.retry,
                      style: AppTextStyles.baseWhite.s14.w600(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
