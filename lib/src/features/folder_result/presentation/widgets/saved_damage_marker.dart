import 'package:flutter/material.dart';

import '../../../../core/constants/string_sheet.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';

/// Marker tổn thất đã lưu — hiện tại vị trí tap trên ảnh kết quả.
class SavedDamageMarker extends StatelessWidget {
  const SavedDamageMarker({
    super.key,
    required this.damageTypeName,
    required this.onTap,
  });

  final String damageTypeName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconSize = 22.r;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: AppColors.damageMarker,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.white, width: 1.5),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.flag_rounded,
              size: 12.r,
              color: AppColors.white,
            ),
          ),
          6.horizontalSpace,
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 5.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    StringSheet.addNew,
                    style: AppTextStyles.base.s10.w600().copyWith(
                          color: AppColors.damageMarker,
                          letterSpacing: 0.4,
                        ),
                  ),
                  1.verticalSpace,
                  Text(
                    damageTypeName,
                    style: AppTextStyles.base.s12.w700().copyWith(
                          color: AppColors.black,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
