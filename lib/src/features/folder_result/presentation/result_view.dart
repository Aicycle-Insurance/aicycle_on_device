import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/string_sheet.dart';
import '../../../core/di/injection.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/screen_utils.dart';
import 'controller/result_controller.dart';
import 'widgets/result_card.dart';
import 'widgets/step_line.dart';

class ResultView extends StatefulWidget {
  const ResultView({
    super.key,
    required this.sessionId,
    required this.capturedPhotos,
    this.onAngleUploaded,
    this.onComplete,
    this.onAddPhoto,
  });

  final String sessionId;

  /// Reference to CameraController's captured photo path map.
  final Map<int, List<String>> capturedPhotos;

  /// Called after each angle is fully uploaded — camera strips those photos
  /// so a repeated "next" press won't re-upload them.
  final void Function(int angleId)? onAngleUploaded;
  final Function(dynamic result)? onComplete;

  /// Hành vi nút "Thêm ảnh tổn thất". Mặc định (null) là pop về màn trước
  /// (camera). Bootstrap có thể truyền hành vi khác (vd push lại camera khi
  /// folder đã có sẵn kết quả).
  final void Function(BuildContext context)? onAddPhoto;

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

  /// "Thêm ảnh tổn thất": dùng hành vi do nơi push truyền vào, mặc định pop.
  void _addPhoto() {
    if (widget.onAddPhoto != null) {
      widget.onAddPhoto!(context);
    } else {
      Navigator.of(context).pop();
    }
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
    return Scaffold(
      backgroundColor: AppColors.divider,
      appBar: AppBar(
        centerTitle: true,
        title: Text(StringSheet.carPhoto),
        backgroundColor: AppColors.white,
      ),
      body: Column(
        children: [
          /// step line
          Container(
            height: 68.h,
            padding: EdgeInsets.symmetric(horizontal: 50.h),
            child: Center(
              child: StepLine(
                steps: [
                  StepData(
                    label: StringSheet.scenePhoto,
                    activeIcon: Icons.check_rounded,
                  ),
                  StepData(label: StringSheet.damagePhoto)
                ],
                currentIndex: 1,
              ),
            ),
          ),
          if (_controller.result != null && _controller.result!.isNotEmpty)
            Expanded(
              child: ListView.separated(
                itemCount: _controller.result!.length,
                itemBuilder: (context, index) {
                  return ResultCard(
                    item: _controller.result![index],
                    onAddPhoto: _addPhoto,
                  );
                },
                separatorBuilder: (context, index) {
                  return SizedBox(height: 8.h);
                },
              ),
            )
          else
            Expanded(child: _buildEmpty()),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: AppColors.white,
      child: SafeArea(
        minimum: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
        child: Row(
          children: [
            // Thêm ảnh tổn thất → quay lại camera để chụp thêm.
            Expanded(
              child: FilledButton(
                onPressed: _addPhoto,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryA500,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28.r),
                  ),
                ),
                child: Text(
                  StringSheet.addDamagePhoto,
                  style: AppTextStyles.baseWhite.s14.w600(),
                ),
              ),
            ),
            12.horizontalSpace,
            // Xong → báo host hoàn tất rồi đóng màn kết quả.
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  List<Map<String, dynamic>> result =
                      _controller.result?.map((e) => e.toJson()).toList() ?? [];
                  widget.onComplete?.call(result);
                },
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  side: BorderSide(color: AppColors.primaryA500),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28.r),
                  ),
                ),
                child: Text(
                  StringSheet.done,
                  style: AppTextStyles.base.s14.w600().copyWith(
                        color: AppColors.primaryA500,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48.w,
            color: AppColors.greenA500,
          ),
          12.verticalSpace,
          Text(
            StringSheet.noDamageFound,
            style: AppTextStyles.base.s16.w600().copyWith(
                  color: AppColors.inkA500,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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
