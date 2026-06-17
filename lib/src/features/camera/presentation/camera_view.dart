import 'package:aicycle_yolo/multi_task_yolo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../aicycle_on_device.dart';
import '../../../config/config_holder.dart';
import '../../../core/constants/string_sheet.dart';
import '../../../core/di/injection.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/screen_utils.dart';

import '../../folder_result/presentation/result_view.dart';
import '../data/model/camera_message.dart';
import 'controller/camera_controller.dart';
import 'controller/camera_model_controller.dart';
import 'widgets/bounding_box_overlay.dart';
import 'widgets/camera_bottom_bar.dart';
import 'widgets/camera_corner_bracket.dart';
import 'widgets/camera_guide_sheet.dart';
import 'widgets/camera_top_bar.dart';
import 'widgets/car_progress_dialog.dart';
import 'widgets/tool_tip.dart';

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
  bool _guideShown = false;

  @override
  void initState() {
    super.initState();
    AICycleConfigHolder.init(widget.aiCycleConfig);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

    final sessionId = widget.aiCycleConfig.generalConfig.documentId;
    _cameraController = CameraController(sessionId: sessionId)
      ..loadCachedPhotos()
      ..requestGalleryPermission();

    _modelController = CameraModelController(
      sl.aiModelRepository,
      sl.aicycleFolderRepository,
      sl.authRepository,
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

  void _maybeShowGuide() {
    if (_guideShown) return;
    _guideShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => RotatedBox(
          quarterTurns: 1,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: CameraGuideSheet(
                onStart: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ),
      );
    });
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
    if (confirmed == true) {
      await PhotoSessionCache.instance
          .clearSession(widget.aiCycleConfig.generalConfig.documentId);
    }
    return confirmed ?? false;
  }

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
          _maybeShowGuide();
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

  Widget _buildTooltip() {
    final phase = _cameraController.inspectionPhase;
    final msg = _cameraController.message!;
    return CameraToolTip(
      preffixIcon: msg.icon,
      message: msg.message,
      // ── Close button ────────────────────────────────────────────────────
      // Visible only on panoramicGuide. Pressing it starts damage scanning.
      showCloseButton: phase == InspectionPhase.panoramicGuide,
      onCloseButtonPressed: _cameraController.startDamageScanning,
      // ── Secondary button ─────────────────────────────────────────────────
      // detectionReady → "Thiếu tổn thất"
      // panoramicGuide / continueOrChange → "Chuyển góc"
      showSecondaryButton: phase == InspectionPhase.detectionReady ||
          phase == InspectionPhase.panoramicGuide ||
          phase == InspectionPhase.continueOrChange,
      secondaryButtonLabel: phase == InspectionPhase.detectionReady
          ? StringSheet.missingDamage
          : StringSheet.changeAngle,
      onSecondaryButtonPressed: phase == InspectionPhase.detectionReady
          ? _cameraController.rejectDamage
          : _cameraController.completeCurrentAngle,
      // ── Primary button ("Xác nhận") — only during detectionReady ────────
      showPrimaryButton: phase == InspectionPhase.detectionReady,
      primaryButtonLabel: StringSheet.confirm,
      onPrimaryButtonPressed: _cameraController.confirmDamage,
    );
  }

  bool _canGoNext() {
    final completed = _cameraController.completedSegments;
    if (widget.aiCycleConfig.validateConfig.require4AnglePanoramicPhotos) {
      return completed.length >= 4;
    }
    return completed.isNotEmpty;
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
                segmentModelPath:
                    _modelController.modelPathOf(AiModelType.carPart)!,
                controller: _cameraController.yoloController,
                confidenceThreshold:
                    widget.aiCycleConfig.modelConfig.confidenceThreshold,
                iouThreshold: widget.aiCycleConfig.modelConfig.iouThreshold,
                onStreamingData: _cameraController.onStreamingData,
              ),

              /// Bounding boxes — only during inspection phase
              Positioned.fill(
                child: BoundingBoxOverlay(
                  detections: _cameraController.showBoundingBoxes
                      ? _cameraController.latestDetections
                      : const [],
                ),
              ),

              /// Overlay UI — yellow frame corners only while taking the
              /// panoramic photo, not during damage detail inspection.
              if (!_cameraController.isInspectionMode)
                Positioned(
                  top: 83.h,
                  left: 0.w,
                  right: 0.w,
                  bottom: 115.h,
                  child: CameraFrameCorners(
                    isSuccess:
                        _cameraController.message?.type == MessageType.loading,
                  ),
                ),

              /// Tooltip — buttons depend on inspection phase
              if (_cameraController.message != null)
                Positioned(
                  right: 36.w,
                  top: 105.h,
                  bottom: 140.h,
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: 1,
                      child: _buildTooltip(),
                    ),
                  ),
                ),
              // Top bar
              CameraTopBar(
                isTorchEnabled: _cameraController.isTorchEnabled,
                onClose: () async {
                  final nav = Navigator.of(context);
                  if (await _onWillPop()) nav.pop();
                },
                onToggleFlash: _cameraController.toggleFlash,
              ),

              // Bottom bar
              CameraBottomBar(
                capturedPhotos: _cameraController.capturedPhotos,
                activeSegmentIndex: _cameraController.activeSegmentIndex,
                completedSegments: _cameraController.completedSegments,
                onShowProgress: _showCarProgressDialog,
                showNextButton: _canGoNext(),
                onNext: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ResultView(
                      sessionId: widget.aiCycleConfig.generalConfig.documentId,
                      capturedPhotos: _cameraController.capturedPhotos,
                      onAngleUploaded: _cameraController.removeUploadedPhotos,
                      onComplete: widget.onComplete,
                    ),
                  ),
                ),
              ),

              /// Screen-blink (flash) effect — triggered on every photo capture.
              Positioned.fill(
                top: 83.h,
                bottom: 115.h,
                child: _CaptureFlashOverlay(
                  flashTick: _cameraController.captureFlashTick,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// White screen-blink shown briefly whenever [flashTick] changes — mimics a
/// camera shutter flash at the exact moment a photo is captured.
class _CaptureFlashOverlay extends StatefulWidget {
  const _CaptureFlashOverlay({required this.flashTick});

  final int flashTick;

  @override
  State<_CaptureFlashOverlay> createState() => _CaptureFlashOverlayState();
}

class _CaptureFlashOverlayState extends State<_CaptureFlashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 180),
    );
  }

  @override
  void didUpdateWidget(_CaptureFlashOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.flashTick != oldWidget.flashTick) {
      _controller.forward(from: 0).then((_) => _controller.reverse());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: _controller,
        child: Container(color: Colors.white),
      ),
    );
  }
}
