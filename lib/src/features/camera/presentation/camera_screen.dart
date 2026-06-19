import 'package:aicycle_yolo/multi_task_yolo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../aicycle_on_device.dart';
import '../../../core/constants/string_sheet.dart';
import '../../../core/di/injection.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/screen_utils.dart';
import '../../folder_result/presentation/controller/result_controller.dart';
import '../data/model/camera_message.dart';
import 'controller/camera_controller.dart';
import 'widgets/bounding_box_overlay.dart';
import 'widgets/camera_bottom_bar.dart';
import 'widgets/car_part_label_overlay.dart';
import 'widgets/camera_corner_bracket.dart';
import 'widgets/camera_guide_sheet.dart';
import 'widgets/camera_top_bar.dart';
import 'widgets/car_progress_dialog.dart';
import 'widgets/tool_tip.dart';

/// Màn camera thuần — chụp ảnh giám định. Nhận các đường dẫn model đã được
/// chuẩn bị sẵn (folder + tải model do màn bootstrap [AICycleOnDeviceCamera]
/// lo trước đó).
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.aiCycleConfig,
    required this.carCornerModelPath,
    required this.carDamageModelPath,
    required this.carPartModelPath,
    this.onComplete,
  });

  final AICycleConfig aiCycleConfig;
  final String carCornerModelPath;
  final String carDamageModelPath;
  final String carPartModelPath;
  final Function()? onComplete;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final CameraController _cameraController;
  bool _guideShown = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // Giữ màn hình sáng trong suốt lúc camera đang stream.
    WakelockPlus.enable();

    final sessionId = widget.aiCycleConfig.generalConfig.documentId;
    _cameraController = CameraController(sessionId: sessionId)
      ..loadCachedPhotos();

    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowGuide());
  }

  @override
  void dispose() {
    // Cho phép màn hình tự tắt trở lại khi rời camera.
    WakelockPlus.disable();
    _cameraController.dispose();
    super.dispose();
  }

  void _maybeShowGuide() {
    if (_guideShown || !mounted) return;
    _guideShown = true;
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

  /// Nhấn "Next": upload toàn bộ ảnh (kèm loading), KHÔNG gọi API lấy kết quả,
  /// rồi báo host qua [onComplete] và thoát màn camera. Màn ResultView đã được
  /// loại khỏi flow (vẫn giữ file).
  Future<void> _uploadAndComplete() async {
    final uploadController = ResultController(
      sessionId: widget.aiCycleConfig.generalConfig.documentId,
      capturedPhotos: _cameraController.capturedPhotos,
      repository: sl.resultRepository,
      onAngleUploaded: _cameraController.removeUploadedPhotos,
      fetchResultAfterUpload: false,
    );

    final navigator = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: RotatedBox(
          quarterTurns: 1,
          child: Center(
            child: AnimatedBuilder(
              animation: uploadController,
              builder: (_, __) => _buildUploadingCard(uploadController),
            ),
          ),
        ),
      ),
    );

    await uploadController.start();
    if (!mounted) {
      uploadController.dispose();
      return;
    }
    navigator.pop(); // đóng dialog loading

    if (uploadController.status == ResultStatus.error) {
      final message = uploadController.errorMessage;
      uploadController.dispose();
      _showUploadError(message);
      return;
    }
    uploadController.dispose();

    // Upload xong → báo host (không có kết quả vì đã bỏ bước fetch) rồi thoát.
    widget.onComplete?.call();
    navigator.pop();
  }

  Widget _buildUploadingCard(ResultController controller) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(24.r),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48.w,
              height: 48.w,
              child: CircularProgressIndicator(
                value: controller.uploadProgress > 0
                    ? controller.uploadProgress
                    : null,
                strokeWidth: 4,
                color: AppColors.primaryA500,
                backgroundColor: AppColors.primaryA200,
              ),
            ),
            16.verticalSpace,
            Text(
              StringSheet.uploadingPhotos(
                controller.uploadedCount,
                controller.totalCount,
              ),
              style: AppTextStyles.base.s14.ink400Color,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showUploadError(String? message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => RotatedBox(
        quarterTurns: 1,
        child: AlertDialog(
          title: Text(
            StringSheet.unknownError,
            style: AppTextStyles.base.s16.w600(),
          ),
          content: Text(
            message ?? StringSheet.unknownError,
            style: AppTextStyles.base.s14.ink400Color,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                StringSheet.cancel,
                style: AppTextStyles.base.s14.w600(),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _uploadAndComplete();
              },
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
    );
  }

  @override
  Widget build(BuildContext context) {
    ScreenUtil.init(context);
    final model = widget.aiCycleConfig.modelConfig;
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
                detectModelPath: widget.carDamageModelPath,
                classifyModelPath: widget.carCornerModelPath,
                secondDetectModelPath: widget.carPartModelPath,
                controller: _cameraController.yoloController,
                secondDetectConfidenceThreshold: model.carPartConfThreshold,
                secondDetectIouThreshold: model.carPartIouThreshold,
                classifyConfidenceThreshold: model.carCornerConfThreshold,
                detectConfidenceThreshold: model.carDamageConfThreshold,
                detectIouThreshold: model.carDamageIouThreshold,
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

              /// Nhãn tên bộ phận — chỉ khi đang căn chỉnh ảnh toàn cảnh.
              Positioned.fill(
                child: CarPartLabelOverlay(
                  detections: _cameraController.latestCarPartDetections,
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
                onNext: _uploadAndComplete,
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
