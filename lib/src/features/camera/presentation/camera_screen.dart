import 'dart:async';

import '../../../yolo/multi_task_yolo_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../aicycle_on_device.dart';
import '../../../core/cache/photo_session_cache.dart';
import '../../../core/constants/string_sheet.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/upload/photo_upload_queue.dart';
import '../../../core/utils/screen_utils.dart';
import '../data/model/camera_message.dart';
import 'controller/camera_controller.dart';
import 'widgets/bounding_box_overlay.dart';
import 'widgets/camera_bottom_bar.dart';
import 'widgets/car_part_label_overlay.dart';
import 'widgets/camera_corner_bracket.dart';
import 'widgets/camera_guide_sheet.dart';
import 'widgets/camera_top_bar.dart';
import 'widgets/capture_freeze_overlay.dart';
import 'widgets/car_progress_dialog.dart';
import 'widgets/manual_capture_hint_hand.dart';
import 'widgets/tool_tip.dart';
import 'widgets/view_result_button.dart';

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
    this.licensePlateModelPath,
    this.onComplete,
    this.onViewResult,
  });

  final AICycleConfig aiCycleConfig;
  final String carCornerModelPath;
  final String carDamageModelPath;
  final String carPartModelPath;

  /// Model OCR biển số (đã tải/quản lý qua model manager, network-only).
  /// Null → native bỏ qua OCR.
  final String? licensePlateModelPath;
  final Function()? onComplete;

  /// Bấm "Xem kết quả": trả ảnh đã chụp lên bootstrap để chuyển sang pha upload
  /// (bootstrap sẽ gỡ camera này khỏi cây → giải phóng tài nguyên).
  final void Function(Map<int, List<String>> photos)? onViewResult;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  late final CameraController _cameraController;
  bool _guideShown = false;
  bool _resultRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockPortraitUp();
    // Giữ màn hình sáng trong suốt lúc camera đang stream.
    WakelockPlus.enable();

    final sessionId = widget.aiCycleConfig.generalConfig.documentId;
    _cameraController = CameraController(
      sessionId: sessionId,
      require4Angles:
          widget.aiCycleConfig.validateConfig.require4AnglePanoramicPhotos,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreAndStart());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Cho phép màn hình tự tắt trở lại khi rời camera.
    WakelockPlus.disable();
    _cameraController.dispose();
    super.dispose();
  }

  void _lockPortraitUp() {
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  }

  Future<void> _restoreAndStart() async {
    await _cameraController.loadCachedPhotos();
    if (!mounted) return;
    if (_cameraController.capturedPhotos.isNotEmpty) {
      _guideShown = true;
      _cameraController.startCapture();
      return;
    }
    _maybeShowGuide();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _lockPortraitUp();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lockPortraitUp();
    }
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
              onStart: () {
                // Mở cổng streaming: trước khi bấm nút này, output YOLO bị bỏ qua.
                _cameraController.startCapture();
                Navigator.of(context).pop();
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    final sessionId = widget.aiCycleConfig.generalConfig.documentId;
    if (widget.aiCycleConfig.generalConfig.alwaysCache) {
      // Ảnh đã được ghi xuống PhotoSessionCache ngay sau mỗi lần chụp; khi bật
      // alwaysCache thì rời camera không hỏi xoá cache nữa.
      _cameraController.stopCamera();
      return true;
    }
    final hasCachedSession =
        await PhotoSessionCache.instance.hasSessionData(sessionId);
    if (!mounted) return false;
    if (_cameraController.capturedPhotos.isEmpty && !hasCachedSession) {
      return true;
    }
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
      // Dừng camera trước khi pop để native cleanup không chặn UI trong dispose().
      _cameraController.stopCamera();
      await PhotoUploadQueue.instance.clearSession(sessionId);
      await PhotoSessionCache.instance.clearSession(sessionId);
    }
    return confirmed ?? false;
  }

  Widget _buildTooltip() {
    final phase = _cameraController.messagePhase;
    final msg = _cameraController.message!;
    final isDetectionReady = phase == InspectionPhase.detectionReady;
    return CameraToolTip(
      preffixIcon: msg.icon,
      message: msg.message,
      // Không còn nút "Chuyển góc"; chuyển góc được xử lý tự động khi model
      // nhận diện user đã di chuyển sang góc xe khác.
      showCloseButton: false,
      // ── Secondary button ─────────────────────────────────────────────────
      // detectionReady → "Thiếu tổn thất"
      showSecondaryButton: isDetectionReady,
      secondaryButtonLabel: StringSheet.missingDamage,
      onSecondaryButtonPressed: _cameraController.rejectDamage,
      // detectionReady → "Xác nhận".
      showPrimaryButton: isDetectionReady,
      primaryButtonLabel: StringSheet.confirm,
      onPrimaryButtonPressed: () {
        _cameraController.confirmDamage();
      },
    );
  }

  bool get _showManualCaptureHint =>
      _cameraController.message?.message == StringSheet.noDamageDetectedGuide;

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
          completedTakesPriority: _cameraController.completedTakesPriority,
        ),
      ),
    );
  }

  /// "Xem kết quả": snapshot ảnh rồi báo bootstrap chuyển sang pha upload.
  /// Bootstrap sẽ giữ camera phía sau thêm một nhịp ngắn để UploadView render
  /// trước, sau đó mới tháo platform view và cleanup camera/model native.
  void _goToResult() {
    if (_resultRequested) return;
    _resultRequested = true;
    _cameraController.stopCamera();
    unawaited(WakelockPlus.disable());
    final photos = {
      for (final e in _cameraController.capturedPhotos.entries)
        e.key: List<String>.from(e.value),
    };
    widget.onViewResult?.call(photos);
  }

  @override
  Widget build(BuildContext context) {
    ScreenUtil.init(context, forcePortrait: true);
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
        body: LayoutBuilder(
          builder: (context, constraints) {
            // Camera preview là aspect-fill phủ toàn bộ vùng này; top bar (83.h)
            // và bottom bar (115.h) che 2 đầu. Báo controller khung user thực sự
            // thấy để native crop ảnh chụp về đúng vùng đó (tránh ảnh "dài hơn").
            final h = constraints.maxHeight;
            if (h > 0) {
              _cameraController.setCaptureViewport(
                top: 83.h / h,
                bottom: (h - 115.h) / h,
              );
            }
            return Stack(
              children: [
                // Platform view dựng MỘT lần — đặt NGOÀI AnimatedBuilder để
                // không bị rebuild theo từng frame inference (notifyListeners).
                MultiTaskYOLOView(
                  detectModelPath: widget.carDamageModelPath,
                  classifyModelPath: widget.carCornerModelPath,
                  secondDetectModelPath: widget.carPartModelPath,
                  // OCR biển số: chỉ dùng model đã tải/quản lý qua network
                  // (null khi chưa tải → native bỏ qua OCR).
                  ocrModelPath: widget.licensePlateModelPath,
                  ocrConfidenceThreshold: model.licensePlateConfThreshold,
                  controller: _cameraController.yoloController,
                  secondDetectConfidenceThreshold: model.carPartConfThreshold,
                  secondDetectIouThreshold: model.carPartIouThreshold,
                  classifyConfidenceThreshold: model.carCornerConfThreshold,
                  detectConfidenceThreshold: model.carDamageConfThreshold,
                  detectIouThreshold: model.carDamageIouThreshold,
                  onStreamingData: _cameraController.onStreamingData,
                ),

                // Các overlay động gom trong 1 AnimatedBuilder phủ kín màn hình.
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _cameraController,
                    builder: (context, _) => Stack(
                      children: [
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
                            detections:
                                _cameraController.latestCarPartDetections,
                          ),
                        ),

                        /// Overlay UI — khung góc vàng hiển thị xuyên suốt quá
                        /// trình chụp. Viền success hiện khi: đang "giữ yên"
                        /// chờ OCR (loading), hoặc nháy theo mỗi lần chụp ảnh
                        /// (đồng bộ với blink; bấm "Xác nhận" giữ theo thời
                        /// gian message chụp thành công).
                        Positioned(
                          top: 83.h,
                          left: 0.w,
                          right: 0.w,
                          bottom: 115.h,
                          child: CameraFrameCorners(
                            isSuccess: _cameraController.cornerSuccessActive ||
                                _cameraController.message?.type ==
                                    MessageType.loading,
                          ),
                        ),

                        /// Tooltip — buttons depend on inspection phase.
                        /// The app is portrait-locked, while users hold the phone
                        /// landscape-left. Keep the tooltip rotated for readability,
                        /// but anchor it near the portrait right edge so it appears
                        /// at the top of the landscape view instead of the center.
                        if (_cameraController.message != null)
                          Positioned(
                            top: 105.h,
                            bottom: 140.h,
                            right: 24.w,
                            child: Center(
                              widthFactor: 1,
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

                        // Bottom bar (thumbnail + nút chụp thủ công + progress ring)
                        CameraBottomBar(
                          capturedPhotos: _cameraController.capturedPhotos,
                          activeSegmentIndex:
                              _cameraController.activeSegmentIndex,
                          completedSegments:
                              _cameraController.completedSegments,
                          completedTakesPriority:
                              _cameraController.completedTakesPriority,
                          onShowProgress: _showCarProgressDialog,
                          onCapture: _cameraController.manualCapture,
                        ),
                        if (_showManualCaptureHint)
                          Positioned(
                            left: 0,
                            right: 0.w,
                            bottom: 112.h,
                            child: Center(
                              child: ManualCaptureHintHand(
                                width: 73.r,
                                height: 63.r,
                              ),
                            ),
                          ),

                        /// Nút "Xem kết quả" (2 bước chống chạm nhầm) — góc dưới phải.
                        if (_canGoNext())
                          Positioned(
                            left: 24.w,
                            bottom: 130.h,
                            child: RotatedBox(
                              quarterTurns: 1,
                              child: ViewResultButton(onPressed: _goToResult),
                            ),
                          ),

                        /// Ảnh vừa chụp dừng hình rồi co nhỏ về thumbnail góc
                        /// dưới trái — phải nằm trên bottom bar để "hạ cánh"
                        /// đúng vào ô thumbnail.
                        Positioned.fill(
                          child: CaptureFreezeOverlay(
                            tick: _cameraController.captureFreezeTick,
                            photoPath: _cameraController.captureFreezePath,
                            holdDuration:
                                _cameraController.captureFreezeHoldDuration,
                            shrinkDuration:
                                _cameraController.captureFreezeShrinkDuration,
                            topBarHeight: 83.h,
                            bottomBarHeight: CameraBottomBar.barHeight.h,
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
              ],
            );
          },
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
