import 'package:flutter/material.dart';

import '../../../../core/constants/string_sheet.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';
import '../../domain/entity/inspection_result.dart';
import 'angle_thumb.dart';

/// Bottom bar của ResultView — 3 vùng: label | góc xe | nút hành động.
class ResultBottomBar extends StatelessWidget {
  const ResultBottomBar({
    super.key,
    required this.selectedAngle,
    required this.angleLabel,
    required this.grouped,
    required this.onAngleSelected,
    required this.onEstimate,
    this.isSubmitting = false,
  });

  final int selectedAngle;
  final String angleLabel;
  final Map<int, List<ResultImage>> grouped;
  final ValueChanged<int> onAngleSelected;
  final VoidCallback onEstimate;
  final bool isSubmitting;

  static const int _angleCount = 4;
  static const double _thumbDesignW = 84;
  static const double _thumbDesignH = 44;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bottombarBackground,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: SizedBox(
          height: 70.h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 1, child: _buildLabelSection()),
              Expanded(flex: 2, child: _buildAngleSection()),
              Expanded(flex: 1, child: _buildActionSection()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabelSection() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Góc ${selectedAngle + 1}: ',
              style: AppTextStyles.base.s14.w500().copyWith(
                    color: AppColors.inkA400,
                  ),
            ),
            TextSpan(
              text: angleLabel,
              style: AppTextStyles.base.s14.w600().copyWith(
                    color: AppColors.primaryA600,
                  ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildAngleSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 6.w;
        final totalGaps = gap * (_angleCount - 1);
        final maxW = constraints.maxWidth;

        final designW = _thumbDesignW.w;
        final designH = _thumbDesignH.h;
        final fitW = (maxW - totalGaps) / _angleCount;
        final thumbW = fitW < designW ? fitW : designW;
        final thumbH = thumbW * (designH / designW);

        return Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              StringSheet.resultAngleLabels.length,
              (i) => Padding(
                padding: EdgeInsets.only(
                  right: i < StringSheet.resultAngleLabels.length - 1
                      ? gap
                      : 0,
                ),
                child: AngleThumb(
                  index: i,
                  selected: i == selectedAngle,
                  hasImages: (grouped[i] ?? []).isNotEmpty,
                  onTap: isSubmitting ? null : () => onAngleSelected(i),
                  width: thumbW,
                  height: thumbH,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionSection() {
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerRight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: FilledButton(
                  onPressed: isSubmitting ? null : onEstimate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryA600,
                    disabledBackgroundColor: AppColors.primaryA300,
                    minimumSize: Size(0, 45.h),
                    padding: EdgeInsets.symmetric(horizontal: 14.w),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                  ),
                  child: isSubmitting
                      ? SizedBox(
                          width: 18.r,
                          height: 18.r,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.white,
                          ),
                        )
                      : Text(
                          StringSheet.estimateDamage,
                          style: AppTextStyles.base.s14.w700().copyWith(
                                color: AppColors.white,
                              ),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
