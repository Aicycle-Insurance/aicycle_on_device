import 'package:flutter/material.dart';

import '../../../../core/constants/string_sheet.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';
import 'icon_button.dart';

class CameraTopBar extends StatelessWidget {
  const CameraTopBar({
    super.key,
    required this.isTorchEnabled,
    required this.onClose,
    required this.onToggleFlash,
  });

  final bool isTorchEnabled;
  final VoidCallback onClose;
  final VoidCallback onToggleFlash;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 83.h,
      color: AppColors.black,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CIconButton(
            onPressed: onClose,
            icon: Icon(
              Icons.clear_rounded,
              size: 24.r,
              color: AppColors.white,
            ),
          ),
          Text(
            StringSheet.carPhoto,
            style: AppTextStyles.baseWhite.s16.w600(),
          ),
          CIconButton(
            onPressed: onToggleFlash,
            icon: Icon(
              isTorchEnabled
                  ? Icons.flash_on_rounded
                  : Icons.flash_off_rounded,
              size: 24.r,
              color: isTorchEnabled ? AppColors.primaryA500 : AppColors.white,
            ),
          ),
        ],
      ),
    );
  }
}
