import 'package:flutter/material.dart';

import '../../../../core/constants/string_sheet.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';
import 'car_progress_ring.dart';

class CarProgressDialog extends StatelessWidget {
  const CarProgressDialog({
    super.key,
    required this.activeIndex,
    required this.completedIndices,
    this.completedTakesPriority = false,
  });

  final int? activeIndex;
  final Set<int> completedIndices;
  final bool completedTakesPriority;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: 1,
      child: Align(
        alignment: Alignment.center,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            width: 370.w,
            height: 160.h,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(16.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                RotatedBox(
                  quarterTurns: 3,
                  child: CarProgressRing(
                    size: 70.r,
                    activeIndex: activeIndex,
                    completedIndices: completedIndices,
                    completedTakesPriority: completedTakesPriority,
                  ),
                ),
                SizedBox(width: 16.w),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LegendItem(
                      color: const Color(0xFFFFD53E),
                      label: StringSheet.cornerNeedsPhoto,
                    ),
                    SizedBox(height: 24.w),
                    _LegendItem(
                      color: AppColors.greenA500,
                      label: StringSheet.cornerCaptured,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28.r,
          height: 14.r,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4.r),
          ),
        ),
        SizedBox(width: 8.w),
        Text(label, style: AppTextStyles.base.s12.ink400Color),
      ],
    );
  }
}
