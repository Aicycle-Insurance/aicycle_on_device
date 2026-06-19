import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/constants/string_sheet.dart';
import '../../../core/di/injection.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/screen_utils.dart';
import '../../folder_result/presentation/controller/result_controller.dart';

/// Màn splash upload: nhận ảnh đã chụp từ camera (camera đã bị đóng để giải
/// phóng tài nguyên), upload toàn bộ rồi gọi [onComplete] và thoát. KHÔNG gọi
/// API lấy kết quả (đã bỏ ResultView khỏi flow).
class UploadView extends StatefulWidget {
  const UploadView({
    super.key,
    required this.sessionId,
    required this.capturedPhotos,
    this.onComplete,
  });

  final String sessionId;
  final Map<int, List<Uint8List>> capturedPhotos;
  final Function()? onComplete;

  @override
  State<UploadView> createState() => _UploadViewState();
}

class _UploadViewState extends State<UploadView> {
  late final ResultController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ResultController(
      sessionId: widget.sessionId,
      capturedPhotos: widget.capturedPhotos,
      repository: sl.resultRepository,
      fetchResultAfterUpload: false,
    );
    _run();
  }

  Future<void> _run() async {
    await _controller.start();
    if (!mounted) return;
    if (_controller.status == ResultStatus.error) {
      // Hiếm khi xảy ra (lỗi từng ảnh đã được skip) — để UI hiện retry.
      setState(() {});
      return;
    }
    // Upload xong → báo host, để host tự quyết định action tiếp theo
    widget.onComplete?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ScreenUtil.init(context);
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (_controller.status == ResultStatus.error) {
            return _buildError();
          }
          return _buildUploading();
        },
      ),
    );
  }

  Widget _buildUploading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 56.w,
            height: 56.w,
            child: CircularProgressIndicator(
              value: _controller.uploadProgress > 0
                  ? _controller.uploadProgress
                  : null,
              strokeWidth: 4,
              color: AppColors.primaryA500,
              backgroundColor: AppColors.primaryA200,
            ),
          ),
          20.verticalSpace,
          Text(
            StringSheet.uploadingPhotos(
              _controller.uploadedCount,
              _controller.totalCount,
            ),
            style: AppTextStyles.base.s14.ink400Color,
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
            16.verticalSpace,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () {
                    widget.onComplete?.call();
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    StringSheet.cancel,
                    style: AppTextStyles.base.s14.w600(),
                  ),
                ),
                12.horizontalSpace,
                FilledButton(
                  onPressed: _run,
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
    );
  }
}
