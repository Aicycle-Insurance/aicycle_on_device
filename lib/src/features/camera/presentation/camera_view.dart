import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../aicycle_on_device.dart';
import '../../../config/config_holder.dart';
import '../../../core/constants/string_sheet.dart';
import '../../../core/di/injection.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/screen_utils.dart';
import 'controller/camera_model_controller.dart';

class AICycleOnDeviceCamera extends StatefulWidget {
  const AICycleOnDeviceCamera({
    super.key,
    required this.aiCycleConfig,
    this.onError,
    this.onComplete,
    this.carCornerModelPath,
    this.carDamageModelPath,
    this.carPartModelPath,
  });

  final AICycleConfig aiCycleConfig;
  final Function(String error)? onError;
  final Function(dynamic data)? onComplete;
  final String? carCornerModelPath;
  final String? carDamageModelPath;
  final String? carPartModelPath;

  @override
  State<AICycleOnDeviceCamera> createState() => _AICycleOnDeviceCameraState();
}

class _AICycleOnDeviceCameraState extends State<AICycleOnDeviceCamera> {
  late final CameraModelController _controller;

  @override
  void initState() {
    super.initState();
    AICycleConfigHolder.init(widget.aiCycleConfig);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _controller = CameraModelController(
      sl.aiModelRepository,
      sl.aicycleFolderRepository,
    )..onError = (message) => widget.onError?.call(message);

    _controller.init(
      widget.aiCycleConfig,
      {
        AiModelType.carCorner: widget.carCornerModelPath,
        AiModelType.carDamage: widget.carDamageModelPath,
        AiModelType.carPart: widget.carPartModelPath,
      },
    );
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
        if (_controller.folderError != null) {
          return _buildError(
            _controller.folderError!,
            onRetry: _controller.retryFolder,
          );
        }
        if (!_controller.folderReady) {
          return _buildLoading(StringSheet.creatingFolder);
        }
        if (_controller.isPreparing) return _buildPreparing();
        if (_controller.isReady) return _buildCamera();
        return _buildError(
          _controller.modelError ?? StringSheet.requirementHint,
          onRetry: _controller.retryModels,
        );
      },
    );
  }

  Widget _buildLoading(String message) {
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
            Text(message, style: AppTextStyles.base.s14.ink400Color),
          ],
        ),
      ),
    );
  }

  Widget _buildPreparing() {
    final type = _controller.downloadingType;
    final progress = _controller.downloadProgress;
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48.w,
              height: 48.w,
              child: CircularProgressIndicator(
                value: type != null && progress > 0 ? progress : null,
                strokeWidth: 3,
                color: AppColors.primaryA500,
                backgroundColor: AppColors.primaryA200,
              ),
            ),
            16.verticalSpace,
            Text(
              type != null
                  ? StringSheet.downloadingModel(type.displayName)
                  : StringSheet.preparingModels,
              style: AppTextStyles.base.s14.ink400Color,
            ),
            if (type != null) ...[
              4.verticalSpace,
              Text(
                '${(progress * 100).round()}%',
                style: AppTextStyles.base.s12.w600().primaryColor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildError(String message, {required VoidCallback onRetry}) {
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
                    onPressed: onRetry,
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

  Widget _buildCamera() {
    // TODO: Tích hợp camera + aicycle_yolo với các model path ở trên.
    return const Placeholder();
  }
}
