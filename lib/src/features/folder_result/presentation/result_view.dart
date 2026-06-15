import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/string_sheet.dart';
import '../../../core/di/injection.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/screen_utils.dart';
import 'controller/result_controller.dart';

class ResultView extends StatefulWidget {
  const ResultView({
    super.key,
    required this.sessionId,
    required this.capturedPhotos,
    this.onAngleUploaded,
    this.onComplete,
  });

  final String sessionId;

  /// Reference to CameraController's capturedPhotos map.
  final Map<int, List<Uint8List>> capturedPhotos;

  /// Called after each angle is fully uploaded — camera strips those photos
  /// so a repeated "next" press won't re-upload them.
  final void Function(int angleId)? onAngleUploaded;
  final Function(dynamic result)? onComplete;

  @override
  State<ResultView> createState() => _ResultViewState();
}

class _ResultViewState extends State<ResultView> {
  late final ResultController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ResultController(
      sessionId: widget.sessionId,
      capturedPhotos: widget.capturedPhotos,
      repository: sl.resultRepository,
      onAngleUploaded: widget.onAngleUploaded,
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ScreenUtil.init(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.backgroundLight,
        body: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            switch (_controller.status) {
              case ResultStatus.uploading:
                return _buildUploading();
              case ResultStatus.fetchingResult:
                return _buildFetchingResult();
              case ResultStatus.success:
                return _buildResult();
              case ResultStatus.error:
                return _buildError();
            }
          },
        ),
      ),
    );
  }

  Widget _buildUploading() {
    final uploaded = _controller.uploadedCount;
    final total = _controller.totalCount;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 56.w,
            height: 56.w,
            child: CircularProgressIndicator(
              value: _controller.uploadProgress,
              strokeWidth: 4,
              color: AppColors.primaryA500,
              backgroundColor: AppColors.primaryA200,
            ),
          ),
          20.verticalSpace,
          Text(
            StringSheet.uploadingPhotos(uploaded, total),
            style: AppTextStyles.base.s14.ink400Color,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFetchingResult() {
    return Center(
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
            StringSheet.fetchingResult,
            style: AppTextStyles.base.s14.ink400Color,
          ),
        ],
      ),
    );
  }

  Widget _buildResult() {
    // Notify the host app, then show placeholder.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onComplete?.call(_controller.result);
    });
    return const SizedBox.expand();
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 40.w, color: AppColors.redA400),
            12.verticalSpace,
            Text(
              _controller.errorMessage ?? StringSheet.unknownError,
              style: AppTextStyles.base.s14.ink400Color,
              textAlign: TextAlign.center,
            ),
            20.verticalSpace,
            FilledButton(
              onPressed: _controller.retry,
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
}
