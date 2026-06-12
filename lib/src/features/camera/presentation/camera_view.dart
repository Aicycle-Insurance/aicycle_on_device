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

  /// Cấu hình SDK
  final AICycleConfig aiCycleConfig;

  /// Callback when initialization fails
  final Function(String error)? onError;

  /// Callback when initialization succeeds.
  /// If provided, the widget will not automatically navigate to the default flow.
  final Function(dynamic data)? onComplete;

  /// Đường dẫn đến model corner detection (nếu có)
  final String? carCornerModelPath;

  /// Đường dẫn đến model damage detection (nếu có)
  final String? carDamageModelPath;

  /// Đường dẫn đến model part detection (nếu có)
  final String? carPartModelPath;

  @override
  State<AICycleOnDeviceCamera> createState() => _AICycleOnDeviceCameraState();
}

class _AICycleOnDeviceCameraState extends State<AICycleOnDeviceCamera> {
  late final CameraModelController _modelController;

  @override
  void initState() {
    super.initState();
    // Make config available package-wide (DioClient, LoggerService, camera, ...)
    AICycleConfigHolder.init(widget.aiCycleConfig);
    // Lock orientation to portrait when using the package
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    // Path nào null sẽ được tự tải version mới nhất trước khi mở camera
    _modelController = CameraModelController(sl.aiModelRepository)
      ..onPrepareError = (message) => widget.onError?.call(message);
    _modelController.prepare({
      AiModelType.carCorner: widget.carCornerModelPath,
      AiModelType.carDamage: widget.carDamageModelPath,
      AiModelType.carPart: widget.carPartModelPath,
    });
  }

  @override
  void dispose() {
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ScreenUtil.init(context);
    return AnimatedBuilder(
      animation: _modelController,
      builder: (context, _) {
        if (_modelController.isPreparing) return _buildPreparing();
        // Chỉ mở camera khi đã đủ model cho cả 3 loại
        if (_modelController.isReady) return _buildCamera();
        return _buildError(
          _modelController.error ?? StringSheet.requirementHint,
        );
      },
    );
  }

  Widget _buildPreparing() {
    final downloadingType = _modelController.downloadingType;
    final progress = _modelController.downloadProgress;
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
                value:
                    downloadingType != null && progress > 0 ? progress : null,
                strokeWidth: 3,
                color: AppColors.primaryA500,
                backgroundColor: AppColors.primaryA200,
              ),
            ),
            16.verticalSpace,
            Text(
              downloadingType != null
                  ? StringSheet.downloadingModel(downloadingType.displayName)
                  : StringSheet.preparingModels,
              style: AppTextStyles.base.s14.ink400Color,
            ),
            if (downloadingType != null) ...[
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
              FilledButton(
                onPressed: _modelController.retry,
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
        ),
      ),
    );
  }

  Widget _buildCamera() {
    // Model đã sẵn sàng: _modelController.modelPathOf(type)
    // TODO: Tích hợp camera + aicycle_yolo với các model path ở trên.
    return const Placeholder();
  }
}
