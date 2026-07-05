import 'dart:async';
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

/// Callback bắn ra mỗi khi MỘT ảnh upload thành công.
///
/// [data] là body JSON server trả về cho ảnh vừa upload.
typedef OnImageUploaded = void Function(Map<String, dynamic> data);

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
    this.onImageUploaded,
    this.carCornerModelPath,
    this.carDamageModelPath,
    this.carPartModelPath,
    this.licensePlateModelPath,
  });

  final AICycleConfig aiCycleConfig;
  final Function(String error)? onError;
  final Function()? onComplete;

  /// Gọi mỗi khi một ảnh upload thành công, kèm data server trả về.
  final OnImageUploaded? onImageUploaded;
  final String? carCornerModelPath;
  final String? carDamageModelPath;
  final String? carPartModelPath;
  final String? licensePlateModelPath;

  @override
  State<AICycleOnDeviceCamera> createState() => _AICycleOnDeviceCameraState();
}

class _AICycleOnDeviceCameraState extends State<AICycleOnDeviceCamera> {
  static const _resultTransitionHold = Duration(milliseconds: 350);

  late final CameraModelController _modelController;
  Timer? _releaseCameraAfterTransition;

  /// Khi != null: đang ở pha upload (đã bấm "Xem kết quả"). Bootstrap render
  /// UploadView ngay, rồi gỡ CameraScreen sau một nhịp ngắn để tránh cleanup
  /// native chặn frame chuyển màn.
  Map<int, List<Uint8List>>? _uploadPhotos;
  bool _keepCameraDuringResultTransition = false;

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
        AiModelType.licensePlate: widget.licensePlateModelPath,
      },
    );
  }

  @override
  void dispose() {
    _releaseCameraAfterTransition?.cancel();
    _modelController.dispose();
    super.dispose();
  }

  void _openUploadView(Map<int, List<Uint8List>> photos) {
    if (_uploadPhotos != null) return;
    setState(() {
      _uploadPhotos = photos;
      _keepCameraDuringResultTransition = true;
    });

    _releaseCameraAfterTransition?.cancel();
    _releaseCameraAfterTransition = Timer(_resultTransitionHold, () {
      if (!mounted || _uploadPhotos == null) return;
      setState(() => _keepCameraDuringResultTransition = false);
    });
  }

  Widget _buildCamera() => CameraScreen(
        aiCycleConfig: widget.aiCycleConfig,
        carCornerModelPath:
            _modelController.modelPathOf(AiModelType.carCorner)!,
        carDamageModelPath:
            _modelController.modelPathOf(AiModelType.carDamage)!,
        carPartModelPath: _modelController.modelPathOf(AiModelType.carPart)!,
        licensePlateModelPath:
            _modelController.modelPathOf(AiModelType.licensePlate),
        onComplete: widget.onComplete,
        // Bấm "Xem kết quả" → chuyển sang pha upload: bootstrap render
        // UploadView ngay, rồi mới gỡ camera sau một nhịp ngắn.
        onViewResult: _openUploadView,
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
          return _buildReadyContent();
        }
        return _buildError(
          _modelController.modelError ?? StringSheet.requirementHint,
          onRetry: _modelController.retryModels,
        );
      },
    );
  }

  Widget _buildReadyContent() {
    final photos = _uploadPhotos;

    // Render UploadView trước, giữ camera phía sau thêm một nhịp ngắn rồi mới
    // tháo platform view. Cleanup camera/model native có thể nặng; nếu tháo ngay
    // trong cùng frame với nút "Xem kết quả" thì user thấy màn camera khựng.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photos == null || _keepCameraDuringResultTransition)
          _buildCamera()
        else
          const SizedBox.shrink(),
        if (photos != null)
          UploadView(
            sessionId: widget.aiCycleConfig.generalConfig.documentId,
            capturedPhotos: photos,
            onComplete: widget.onComplete,
            onImageUploaded: widget.onImageUploaded,
            onError: widget.onError,
          ),
      ],
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
