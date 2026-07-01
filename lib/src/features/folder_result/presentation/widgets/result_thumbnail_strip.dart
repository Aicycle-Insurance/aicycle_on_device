import 'package:flutter/material.dart';

import '../../../../core/themes/app_colors.dart';
import '../../../../core/utils/screen_utils.dart';
import '../../domain/entity/inspection_result.dart';

/// Strip thumbnail dọc bên phải màn Result
class ResultThumbnailStrip extends StatelessWidget {
  const ResultThumbnailStrip({
    super.key,
    required this.images,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<ResultImage> images;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168.w,
      color: AppColors.white,
      padding: EdgeInsets.symmetric(
        horizontal: 19.w,
        vertical: 18.h,
      ),
      child: ListView.separated(
        itemCount: images.length,
        padding: EdgeInsets.zero,
        separatorBuilder: (_, __) => 8.verticalSpace,
        itemBuilder: (context, index) {
          final isSelected = index == selectedIndex;
          return GestureDetector(
            onTap: () => onSelected(index),
            child: Container(
              width: 130.w,
              height: 92.h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(
                  color:
                      isSelected ? AppColors.primaryA600 : AppColors.divider,
                  width: isSelected ? 3 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5.r),
                child: _StripThumbnail(url: images[index].imageUrl),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StripThumbnail extends StatelessWidget {
  const _StripThumbnail({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return Container(
        color: AppColors.placeholder,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 21.r,
          color: AppColors.inkA300,
        ),
      );
    }
    return Image.network(
      url!,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(color: AppColors.placeholder);
      },
      errorBuilder: (_, __, ___) => Container(
        color: AppColors.placeholder,
        child: Icon(
          Icons.broken_image_outlined,
          size: 20.r,
          color: AppColors.inkA300,
        ),
      ),
    );
  }
}
