import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

import '../../../../core/themes/app_colors.dart';
import '../../../../core/utils/orientation_utils.dart';
import '../../../../core/utils/screen_utils.dart';
import 'car_progress_ring.dart';

class CameraBottomBar extends StatelessWidget {
  const CameraBottomBar({
    super.key,
    required this.capturedPhotos,
    required this.activeSegmentIndex,
    required this.completedSegments,
    required this.onShowProgress,
    this.onCapture,
    this.completedTakesPriority = false,
  });

  final Map<int, List<Uint8List>> capturedPhotos;
  final int? activeSegmentIndex;
  final Set<int> completedSegments;
  final VoidCallback onShowProgress;
  final bool completedTakesPriority;

  /// Chụp ảnh thủ công (nút shutter).
  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        height: 115.h,
        color: AppColors.black,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
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
  Widget _buildShutterButton() {
    return GestureDetector(
      onTap: onCapture,
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
    );
  }

  Widget _buildThumbnail() {
    final lastPhoto = capturedPhotos.values.expand((l) => l).lastOrNull;
    if (lastPhoto != null) {
      return NativeDeviceOrientationReader(
        useSensor: true,
        builder: (context) {
          final orientation =
              NativeDeviceOrientationReader.orientation(context);
          final turns = OrientationUtils.getTurns(orientation);
          return AnimatedRotation(
            turns: turns,
            duration: const Duration(milliseconds: 300),
            child: Container(
              width: 48.w,
              height: 48.w,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: AppColors.white, width: 2),
                image: DecorationImage(
                  image: MemoryImage(lastPhoto),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      );
    }
    return Container(
      width: 48.w,
      height: 48.w,
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Icon(Icons.photo_library_outlined,
          size: 24.r, color: AppColors.white),
    );
  }
}
