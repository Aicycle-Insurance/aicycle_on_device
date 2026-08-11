import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/string_sheet.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';

/// Bottom sheet hướng dẫn chụp ảnh xe toàn cảnh với 4 ảnh mẫu.
class CameraGuideSheet extends StatelessWidget {
  const CameraGuideSheet({super.key, required this.onStart});

  final VoidCallback onStart;

  static const _samples = [
    AppAssets.sample1,
    AppAssets.sample2,
    AppAssets.sample3,
    AppAssets.sample4,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 420.h,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16.r),
      ),
      padding: EdgeInsets.fromLTRB(16.w, 20.w, 16.w, 20.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            StringSheet.captureGuide,
            style: AppTextStyles.base.s14.ink500Color,
          ),
          16.verticalSpace,
          _SampleImages(samples: _samples),
          20.verticalSpace,
          _StartButton(onTap: onStart),
        ],
      ),
    );
  }
}

class _SampleImages extends StatelessWidget {
  const _SampleImages({required this.samples});

  final List<String> samples;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < samples.length; i++) ...[
          Expanded(child: _SampleItem(path: samples[i])),
          if (i < samples.length - 1) 6.horizontalSpace,
        ],
      ],
    );
  }
}

class _SampleItem extends StatelessWidget {
  const _SampleItem({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 93.r,
      height: 84.r,
      decoration: BoxDecoration(
        color: AppColors.primaryA200,
        borderRadius: BorderRadius.circular(12.r),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        path,
        fit: BoxFit.cover,
        package: 'aicycle_on_device',
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 40.w,
      child: FilledButton.icon(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryA500,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
        icon:
            Icon(Icons.camera_alt_outlined, size: 20.w, color: AppColors.white),
        label: Text(
          StringSheet.startCapture,
          style: AppTextStyles.baseWhite.s16.w600(),
        ),
      ),
    );
  }
}
