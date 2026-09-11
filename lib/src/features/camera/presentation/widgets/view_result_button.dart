import 'package:flutter/material.dart';

import '../../../../core/constants/string_sheet.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';

/// Nút "Kết thúc chụp ảnh" nổi trên camera.
class ViewResultButton extends StatelessWidget {
  const ViewResultButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
        decoration: BoxDecoration(
          color: AppColors.primaryA500,
          borderRadius: BorderRadius.circular(28.r),
        ),
        child: Text(
          StringSheet.viewResult,
          style: AppTextStyles.baseWhite.s15.w600(),
        ),
      ),
    );
  }
}

