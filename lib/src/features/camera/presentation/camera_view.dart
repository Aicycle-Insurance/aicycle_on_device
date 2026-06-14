import 'package:aicycle_yolo/multi_task_yolo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

import '../../../../aicycle_on_device.dart';
import '../../../config/config_holder.dart';
import '../../../core/constants/string_sheet.dart';
import '../../../core/di/injection.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/orientation_utils.dart';
import '../../../core/utils/screen_utils.dart';
import 'controller/camera_controller.dart';
import 'controller/camera_model_controller.dart';
import 'widgets/camera_corner_bracket.dart';
import 'widgets/car_progress_dialog.dart';
import 'widgets/car_progress_ring.dart';
import 'widgets/icon_button.dart';

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
  late final CameraModelController _modelController;
  late final CameraController _cameraController;

  @override
  void initState() {
    super.initState();
    AICycleConfigHolder.init(widget.aiCycleConfig);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    _cameraController = CameraController();

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
    _cameraController.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (_cameraController.capturedPhotos.isEmpty) return true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => RotatedBox(
        quarterTurns: 1,
        child: AlertDialog(
          title: Text(
            StringSheet.exitCameraTitle,
            style: AppTextStyles.base.s16.w600(),
          ),
          content: Text(
            StringSheet.exitCameraContent,
            style: AppTextStyles.base.s14.ink400Color,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                StringSheet.cancel,
                style: AppTextStyles.base.s14.w600(),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                StringSheet.exitConfirm,
                style: AppTextStyles.base.s14.w600().copyWith(
                      color: AppColors.redA400,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    ScreenUtil.init(context);
    return AnimatedBuilder(
      animation: _modelController,
      builder: (context, _) {
        // if (_modelController.folderError != null) {
        //   return _buildError(
        //     _modelController.folderError!,
        //     onRetry: _modelController.retryFolder,
        //   );
        // }
        // if (!_modelController.folderReady) {
        //   return _buildLoading(StringSheet.creatingFolder);
        // }
        if (_modelController.isPreparing) return _buildPreparing();
        if (_modelController.isReady) return _buildCamera();
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

  void _showCarProgressDialog() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => AnimatedBuilder(
        animation: _cameraController,
        builder: (_, __) => CarProgressDialog(
          activeIndex: _cameraController.activeSegmentIndex,
          completedIndices: _cameraController.completedSegments,
        ),
      ),
    );
  }

  Widget _buildCamera() {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _onWillPop()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          toolbarHeight: 0,
          backgroundColor: AppColors.black,
          systemOverlayStyle: SystemUiOverlayStyle.light,
        ),
        body: AnimatedBuilder(
          animation: _cameraController,
          builder: (context, _) => Stack(
            children: [
              MultiTaskYOLOView(
                detectModelPath:
                    _modelController.modelPathOf(AiModelType.carDamage)!,
                classifyModelPath:
                    _modelController.modelPathOf(AiModelType.carCorner)!,
                controller: _cameraController.yoloController,
                confidenceThreshold:
                    widget.aiCycleConfig.modelConfig.confidenceThreshold,
                iouThreshold: widget.aiCycleConfig.modelConfig.iouThreshold,
                onStreamingData: _cameraController.onStreamingData,
              ),
              Positioned(
                top: 83.h,
                left: 0.w,
                right: 0.w,
                bottom: 115.h,
                child: CameraFrameCorners(),
              ),
              // Topbar
              Container(
                width: double.infinity,
                height: 83.h,
                color: AppColors.black,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CIconButton(
                      onPressed: () async {
                        final nav = Navigator.of(context);
                        if (await _onWillPop()) nav.pop();
                      },
                      icon: Icon(
                        Icons.clear_rounded,
                        size: 24.r,
                        color: AppColors.white,
                      ),
                    ),
                    Text(
                      StringSheet.carPhoto,
                      style: AppTextStyles.baseWhite.s16.w600(),
                    ),
                    CIconButton(
                      onPressed: _cameraController.toggleFlash,
                      icon: Icon(
                        _cameraController.isTorchEnabled
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        size: 24.r,
                        color: _cameraController.isTorchEnabled
                            ? AppColors.primaryA500
                            : AppColors.white,
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom bar
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  height: 115.h,
                  color: AppColors.black,
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_cameraController.capturedPhotos.isNotEmpty)
                        NativeDeviceOrientationReader(
                          useSensor: true,
                          builder: (context) {
                            final orientation =
                                NativeDeviceOrientationReader.orientation(
                                    context);
                            final turns =
                                OrientationUtils.getTurns(orientation);
                            return AnimatedRotation(
                              turns: turns,
                              duration: const Duration(milliseconds: 300),
                              child: Container(
                                width: 48.w,
                                height: 48.w,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8.r),
                                  border: Border.all(
                                      color: AppColors.white, width: 2),
                                  image: DecorationImage(
                                    image: MemoryImage(
                                      _cameraController.capturedPhotos.last,
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      else
                        Container(
                          width: 48.w,
                          height: 48.w,
                          decoration: BoxDecoration(
                            color: AppColors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Icon(Icons.photo_library_outlined,
                              size: 24.r, color: AppColors.white),
                        ),
                      GestureDetector(
                        onTap: () => _showCarProgressDialog(),
                        child: CarProgressRing(
                          activeIndex: _cameraController.activeSegmentIndex,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
