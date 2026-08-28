import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/themes/app_colors.dart';
import '../../../../core/utils/screen_utils.dart';
import 'car_progress_ring.dart';

class CameraBottomBar extends StatelessWidget {
  const CameraBottomBar({
    super.key,
    required this.previewPath,
    required this.activeSegmentIndex,
    required this.completedSegments,
    required this.onShowProgress,
    this.onCapture,
    this.completedTakesPriority = false,
    this.isCaptureCoolingDown = false,
  });

  /// Chiều cao bar — dùng chung với overlay/animation cần biết vị trí thumbnail.
  static const barHeight = 115.0;

  /// Hình học thumbnail ảnh vừa chụp (góc dưới trái). Hiệu ứng "ảnh co về
  /// thumbnail" ([CaptureFreezeOverlay]) bay đúng vào ô này nên dùng chung số.
  static const thumbnailSize = 48.0;
  static const thumbnailMargin = 16.0;
  static const thumbnailRadius = 8.0;
  static const thumbnailBorderWidth = 2.0;

  /// Ảnh hiển thị ở ô thumbnail, đã được controller giải sẵn (thumbnail 160px
  /// hoặc ảnh gốc). Null = chưa có ảnh nào. Bar không tự dò file: việc đó chỉ
  /// cần làm lại khi danh sách ảnh đổi, không phải mỗi lần build.
  final String? previewPath;

  final int? activeSegmentIndex;
  final Set<int> completedSegments;
  final VoidCallback onShowProgress;
  final bool completedTakesPriority;

  /// Chụp ảnh thủ công (nút shutter).
  final VoidCallback? onCapture;

  /// True khi đang trong cooldown sau lần chụp tay gần nhất — nút shutter
  /// hiển thị mờ và không nhận tap.
  final bool isCaptureCoolingDown;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        height: barHeight.h,
        color: AppColors.black,
        padding: EdgeInsets.symmetric(horizontal: thumbnailMargin.w),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildThumbnail(),
            _buildShutterButton(),
            GestureDetector(
              onTap: onShowProgress,
              child: CarProgressRing(
                activeIndex: activeSegmentIndex,
                completedIndices: completedSegments,
                completedTakesPriority: completedTakesPriority,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Nút chụp thủ công kiểu shutter: vòng trắng ngoài + tròn trắng trong.
  /// Khi [isCaptureCoolingDown] = true: mờ đi và không nhận tap.
  Widget _buildShutterButton() {
    return Opacity(
      opacity: isCaptureCoolingDown ? 0.35 : 1.0,
      child: GestureDetector(
        onTap: isCaptureCoolingDown ? null : onCapture,
        child: Container(
          width: 66.w,
          height: 66.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.white, width: 3),
          ),
          child: Center(
            child: Container(
              width: 52.w,
              height: 52.w,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    final path = previewPath;
    if (path != null) {
      return RotatedBox(
        quarterTurns: 1,
        child: Container(
          width: thumbnailSize.w,
          height: thumbnailSize.w,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(thumbnailRadius.r),
            border:
                Border.all(color: AppColors.white, width: thumbnailBorderWidth),
            image: DecorationImage(
              image: FileImage(File(path)),
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    }
    return Container(
      width: thumbnailSize.w,
      height: thumbnailSize.w,
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(thumbnailRadius.r),
      ),
      child: Icon(Icons.photo_library_outlined,
          size: 24.r, color: AppColors.white),
    );
  }
}
