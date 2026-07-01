import 'package:flutter/material.dart';

import '../../../../core/constants/string_sheet.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';
import '../../domain/entity/inspection_result.dart';
import 'angle_thumb.dart';

/// Bottom bar của ResultView — label trái, 4 góc giữa, nút hành động phải.
class ResultBottomBar extends StatelessWidget {
  const ResultBottomBar({
    super.key,
    required this.selectedAngle,
    required this.angleLabel,
    required this.grouped,
    required this.onAngleSelected,
    required this.onEstimate,
  });

  final int selectedAngle;
  final String angleLabel;
  final Map<int, List<ResultImage>> grouped;
  final ValueChanged<int> onAngleSelected;
  final VoidCallback onEstimate;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: AppColors.bottombarBackground,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16.w + inset.left,
          0,
          1.w + inset.right,
          inset.bottom,
        ),
        child: SizedBox(
          height: 70.h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Góc ${selectedAngle + 1}: ',
                      style: AppTextStyles.base.s16.w500().copyWith(
                            color: AppColors.inkA400,
                          ),
                      maxLines: 1,
                    ),
                    3.verticalSpace,
                    Text(
                      angleLabel,
                      style: AppTextStyles.base.s16.w600().copyWith(
                            color: AppColors.primaryA600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              16.horizontalSpace,
              // 4 thumbnail góc xe
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  StringSheet.resultAngleLabels.length,
                  (i) => Padding(
                    padding: EdgeInsets.only(
                      right: i < StringSheet.resultAngleLabels.length - 1
                          ? 8.w
                          : 0,
                    ),
                    child: AngleThumb(
                      index: i,
                      selected: i == selectedAngle,
                      hasImages: (grouped[i] ?? []).isNotEmpty,
                      onTap: () => onAngleSelected(i),
                    ),
                  ),
                ),
              ),
              30.horizontalSpace,
              FilledButton(
                onPressed: onEstimate,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryA600,
                  minimumSize: Size(0, 45.h),
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                ),
                child: Text(
                  StringSheet.estimateDamage,
                  style: AppTextStyles.base.s14.w700().copyWith(
                        color: AppColors.white,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
