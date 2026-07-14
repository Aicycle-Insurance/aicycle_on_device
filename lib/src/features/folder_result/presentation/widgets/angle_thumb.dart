import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/utils/screen_utils.dart';

/// Thumbnail ảnh minh hoạ cho một góc xe (0–3) trong bottom bar của ResultView.
class AngleThumb extends StatelessWidget {
  const AngleThumb({
    super.key,
    required this.index,
    required this.selected,
    required this.hasImages,
    this.onTap,
    this.width,
    this.height,
  });

  final int index;
  final bool selected;

  /// Góc này có ảnh kết quả hay không — không có thì không nhận tap + mờ đi.
  final bool hasImages;
  final VoidCallback? onTap;

  /// Kích thước tùy chỉnh; mặc định 84×44 theo design.
  final double? width;
  final double? height;

  static const double _defaultWidth = 84;
  static const double _defaultHeight = 44;
  static const double _disabledOpacity = 0.4;

  @override
  Widget build(BuildContext context) {
    final w = width ?? _defaultWidth.w;
    final h = height ?? _defaultHeight.h;
    final enabled = hasImages && onTap != null;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: hasImages ? 1 : _disabledOpacity,
        child: Container(
          width: w,
          height: h,
          padding: EdgeInsets.all(3.r),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(
              color: selected && hasImages
                  ? AppColors.primaryA600
                  : AppColors.divider,
              width: selected && hasImages ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: Image.asset(
              AppAssets.carAngleSamples[index],
              fit: BoxFit.contain,
              package: 'aicycle_on_device',
            ),
          ),
        ),
      ),
    );
  }
}
