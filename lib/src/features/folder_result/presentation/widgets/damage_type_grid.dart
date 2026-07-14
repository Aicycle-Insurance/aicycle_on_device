import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';
import '../models/damage_type_option.dart';

/// Lưới chọn loại tổn thất (3×2).
class DamageTypeGrid extends StatelessWidget {
  const DamageTypeGrid({
    super.key,
    required this.selectedSlug,
    required this.onSelected,
  });

  final String? selectedSlug;
  final ValueChanged<DamageTypeOption> onSelected;

  @override
  Widget build(BuildContext context) {
    // Grid được đặt trong Expanded — không cần shrinkWrap/scroll.
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8.h,
        crossAxisSpacing: 8.w,
        childAspectRatio: 1.35,
      ),
      itemCount: DamageTypeOptions.all.length,
      itemBuilder: (context, index) {
        final option = DamageTypeOptions.all[index];
        final selected = option.slug == selectedSlug;
        return _DamageTypeTile(
          option: option,
          selected: selected,
          onTap: () => onSelected(option),
        );
      },
    );
  }
}

class _DamageTypeTile extends StatelessWidget {
  const _DamageTypeTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final DamageTypeOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? AppColors.primaryA600 : AppColors.inkA400;

    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: selected ? AppColors.primaryA600 : AppColors.inkA200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                option.iconAsset,
                width: 16.r,
                height: 16.r,
                colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                package: 'aicycle_on_device',
              ),
              6.verticalSpace,
              Text(
                option.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.base.s12.w500().copyWith(color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
