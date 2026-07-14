import 'package:flutter/material.dart';

import '../../../../core/constants/string_sheet.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';

/// Nút "Thêm tổn thất" hiện tại vị trí tap trên ảnh.
class AddDamageTapButton extends StatelessWidget {
  const AddDamageTapButton({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20.r,
                height: 20.r,
                decoration: const BoxDecoration(
                  color: AppColors.primaryA600,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.add,
                  size: 18.r,
                  color: AppColors.white,
                ),
              ),
              6.horizontalSpace,
              Text(
                StringSheet.addDamage,
                style: AppTextStyles.baseWhite.s12.w600(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
