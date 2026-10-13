import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/cache/photo_session_cache.dart';
import '../../../core/constants/string_sheet.dart';
import '../../../core/di/injection.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/screen_utils.dart';
import '../../../core/widgets/confirm_dialog.dart';
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
    this.onClose,
    this.onImageUploaded,
    this.onError,
  });

  final String sessionId;
  final Map<int, List<String>> capturedPhotos;

  /// Chỉ gọi khi toàn bộ ảnh đã có kết quả cuối từ server.
  final Function()? onComplete;

  /// User bấm "Huỷ" và xác nhận xoá ảnh → thoát SDK.
  final VoidCallback? onClose;
  final Function(String)? onError;

  /// Gọi mỗi khi một ảnh upload thành công, kèm data server trả về.
  final void Function(Map<String, dynamic> data)? onImageUploaded;

  @override
  State<UploadView> createState() => _UploadViewState();
}

class _UploadViewState extends State<UploadView> with WidgetsBindingObserver {
  late final ResultController _controller;
  bool _isRunning = false;
  bool _completeNotified = false;
  bool _discarding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ResultController(
      sessionId: widget.sessionId,
      capturedPhotos: widget.capturedPhotos,
      repository: sl.resultRepository,
      fetchResultAfterUpload: false,
      onImageUploaded: widget.onImageUploaded,
      onError: widget.onError,
    );
    _run();
  }

  Future<void> _run() async {
    if (_isRunning || _completeNotified) return;
    _isRunning = true;
    try {
      await _controller.start();
    } finally {
      _isRunning = false;
    }
    if (!mounted || _discarding) return;
    if (_controller.status == ResultStatus.error) {
      // Lỗi cục bộ (đọc/ghi hàng đợi) — để UI hiện retry. Lỗi mạng/máy chủ
      // không tới đây: start() vẫn chạy và tự hiện màn lỗi.
      setState(() {});
      return;
    }
    await PhotoSessionCache.instance.clearUploadPending(widget.sessionId);
    // Upload xong → báo host, để host tự quyết định action tiếp theo
    _notifyComplete();
  }

  void _notifyComplete() {
    if (_completeNotified) return;
    _completeNotified = true;
    widget.onComplete?.call();
  }

  void _onRetryPressed() {
    if (_controller.alert != null) {
      unawaited(_controller.retry());
    } else {
      unawaited(_run());
    }
  }

  /// "Huỷ": xác nhận trước vì toàn bộ ảnh chưa tải lên sẽ bị xoá.
  Future<void> _onCancelPressed() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: StringSheet.cancelUploadTitle,
      content: StringSheet.cancelUploadContent(
        _controller.pendingCount,
        _controller.totalCount,
      ),
      cancelText: StringSheet.goBack,
      confirmText: StringSheet.discardAndExit,
      confirmColor: AppColors.redA400,
    );
    if (!confirmed || !mounted || _discarding) return;
    _discarding = true;
    try {
      await _controller.discardSession();
    } catch (error) {
      // User chose to leave: a cleanup failure must not keep them here.
      debugPrint('AICycle discard session failed: $error');
    }
    if (!mounted) return;
    widget.onClose?.call();
    Navigator.of(context).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(_controller.onAppLifecycleChanged(state));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          if (_controller.isRetrying) ...[
            8.verticalSpace,
            Text(
              StringSheet.uploadRetrying,
              style: AppTextStyles.base.s12.ink400Color,
              textAlign: TextAlign.center,
            ),
          ],
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
                  onPressed: _onCancelPressed,
                  child: Text(
                    StringSheet.cancel,
                    style: AppTextStyles.base.s14.w600(),
                  ),
                ),
                12.horizontalSpace,
                FilledButton(
                  onPressed: _onRetryPressed,
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
