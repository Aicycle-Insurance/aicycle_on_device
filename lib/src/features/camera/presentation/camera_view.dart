import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../aicycle_on_device.dart';
import '../../../config/config_holder.dart';
import '../../../core/constants/string_sheet.dart';
import '../../../core/di/injection.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/screen_utils.dart';
import 'camera_screen.dart';
import 'controller/camera_model_controller.dart';
import 'upload_view.dart';

/// Màn bootstrap của SDK: khởi tạo cấu hình, tạo/lấy hồ sơ (folder) và chuẩn bị
/// model, sau đó vào [CameraScreen].
///
/// Đây là điểm vào public của SDK; host push widget này.
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
  final Function()? onComplete;
  final String? carCornerModelPath;
  final String? carDamageModelPath;
  final String? carPartModelPath;

  @override
  State<AICycleOnDeviceCamera> createState() => _AICycleOnDeviceCameraState();
}

class _AICycleOnDeviceCameraState extends State<AICycleOnDeviceCamera> {
  late final CameraModelController _modelController;

  /// Khi != null: đang ở pha upload (đã bấm "Xem kết quả"). CameraScreen bị gỡ
  /// khỏi cây widget → camera dispose (idle/giải phóng), bootstrap hiện UploadView.
  Map<int, List<Uint8List>>? _uploadPhotos;

  @override
  void initState() {
    super.initState();
    AICycleConfigHolder.init(widget.aiCycleConfig);

    _modelController = CameraModelController(
      sl.aiModelRepository,
      sl.aicycleFolderRepository,
    )..onError = (message) => widget.onError?.call(message);

    _modelController.init(
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
    _modelController.dispose();
    super.dispose();
  }

  Widget _buildCamera() => CameraScreen(
        aiCycleConfig: widget.aiCycleConfig,
        carCornerModelPath:
            _modelController.modelPathOf(AiModelType.carCorner)!,
        carDamageModelPath:
            _modelController.modelPathOf(AiModelType.carDamage)!,
        carPartModelPath: _modelController.modelPathOf(AiModelType.carPart)!,
        onComplete: widget.onComplete,
        // Bấm "Xem kết quả" → chuyển sang pha upload: CameraScreen bị gỡ khỏi
        // cây (camera idle/giải phóng), bootstrap render UploadView.
        onViewResult: (photos) => setState(() => _uploadPhotos = photos),
      );

  @override
  Widget build(BuildContext context) {
    ScreenUtil.init(context);
    return AnimatedBuilder(
      animation: _modelController,
      builder: (context, _) {
        if (_modelController.folderError != null) {
          return _buildError(
            _modelController.folderError!,
            onRetry: _modelController.retryFolder,
          );
        }
        if (!_modelController.folderReady) {
          return _buildLoading(StringSheet.creatingFolder);
        }
        if (_modelController.isPreparing) return _buildPreparing();
        if (_modelController.isReady) {
          // Đang upload → hiện UploadView (camera đã được gỡ → idle).
          if (_uploadPhotos != null) {
            return UploadView(
              sessionId: widget.aiCycleConfig.generalConfig.documentId,
              capturedPhotos: _uploadPhotos!,
              onComplete: widget.onComplete,
            );
          }
          // Model tải xong → CameraScreen. ResultView đã bỏ khỏi flow.
          return _buildCamera();
        }
        return _buildError(
          _modelController.modelError ?? StringSheet.requirementHint,
          onRetry: _modelController.retryModels,
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
    final type = _modelController.downloadingType;
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
}
