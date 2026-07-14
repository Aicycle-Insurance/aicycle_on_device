import 'package:flutter/material.dart';

import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';

class CameraToolTip extends StatelessWidget {
  const CameraToolTip({
    super.key,
    required this.message,
    this.preffixIcon,
    this.showPrimaryButton = false,
    this.onPrimaryButtonPressed,
    this.showSecondaryButton = false,
    this.onSecondaryButtonPressed,
    this.primaryButtonLabel,
    this.secondaryButtonLabel,
    this.showCloseButton = true,
    this.onCloseButtonPressed,
  });

  final String message;
  final Widget? preffixIcon;
  final bool showPrimaryButton;
  final VoidCallback? onPrimaryButtonPressed;
  final String? primaryButtonLabel;
  final String? secondaryButtonLabel;
  final bool showSecondaryButton;
  final VoidCallback? onSecondaryButtonPressed;
  final bool showCloseButton;
  final VoidCallback? onCloseButtonPressed;

  static final _buttonShape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));

  static const _buttonPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 8,
  );

  @override
  Widget build(BuildContext context) {
    final maxWidth =
        (MediaQuery.sizeOf(context).longestSide * 0.62).clamp(280.0, 620.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 8.r),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (preffixIcon != null) ...[
              preffixIcon!,
              8.horizontalSpace,
            ],
            Flexible(
              child: Text(
                message,
                style: TextStyle(fontSize: 14.sp, color: AppColors.black),
              ),
            ),
            if (showSecondaryButton && onSecondaryButtonPressed != null) ...[
              6.horizontalSpace,
              FilledButton(
                onPressed: onSecondaryButtonPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.transparent,
                  foregroundColor: AppColors.transparent,
                  padding: _buttonPadding,
                  shape: _buttonShape.copyWith(
                      side: BorderSide(color: AppColors.divider)),
                  elevation: 0,
                ),
                child: Text(
                  secondaryButtonLabel ?? 'Secondary',
                  style: AppTextStyles.base.s14.w600(),
                ),
              ),
            ],
            if (showPrimaryButton && onPrimaryButtonPressed != null) ...[
              6.horizontalSpace,
              FilledButton(
                onPressed: onPrimaryButtonPressed,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryA500,
                  foregroundColor: AppColors.white,
                  padding: _buttonPadding,
                  shape: _buttonShape,
                  elevation: 0,
                ),
                child: Text(
                  primaryButtonLabel ?? 'Primary',
                  style: AppTextStyles.baseWhite.s14.w600(),
                ),
              ),
            ],
            if (showCloseButton) ...[
              6.horizontalSpace,
              InkWell(
                onTap: onCloseButtonPressed,
                child: Icon(
                  Icons.clear_rounded,
                  size: 20.r,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
