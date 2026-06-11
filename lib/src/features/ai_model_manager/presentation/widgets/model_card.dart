import 'package:flutter/material.dart';

import '../../../../core/constants/string_sheet.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';
import '../../data/model/ai_model.dart';

/// Card hiển thị một model: version, ngày tạo, trạng thái chọn,
/// nút tải về / xoá tuỳ theo trạng thái.
class ModelCard extends StatelessWidget {
  const ModelCard({
    super.key,
    required this.model,
    required this.isSelected,
    required this.isDownloaded,
    required this.downloadProgress,
    required this.onDownload,
    required this.onDelete,
    required this.onSelect,
    this.sizeInBytes,
  });

  final AiModel model;
  final bool isSelected;
  final bool isDownloaded;

  /// Kích thước file model (bytes), null nếu chưa xác định được.
  final int? sizeInBytes;

  /// null = không trong quá trình tải.
  final double? downloadProgress;
  final VoidCallback onDownload;
  final VoidCallback onDelete;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isSelected ? AppColors.primaryA500 : AppColors.divider,
          width: isSelected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.inkA500.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: AppColors.transparent,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: isDownloaded ? onSelect : null,
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              children: [
                _buildSelectionIndicator(),
                12.horizontalSpace,
                Expanded(child: _buildInfo()),
                12.horizontalSpace,
                _buildTrailing(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionIndicator() {
    if (isSelected) {
      return Container(
        width: 24.w,
        height: 24.w,
        decoration: const BoxDecoration(
          color: AppColors.primaryA500,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check, size: 16.w, color: AppColors.white),
      );
    }
    return Container(
      width: 24.w,
      height: 24.w,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isDownloaded ? AppColors.primaryA300 : AppColors.inkA200,
          width: 2,
        ),
      ),
    );
  }

  Widget _buildInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          StringSheet.modelVersion(model.version),
          style: AppTextStyles.base.s14.w600().ink500Color,
        ),
        4.verticalSpace,
        Text(
          StringSheet.releasedAt(_formatDate(model.createdDate)),
          style: AppTextStyles.base.s12.ink400Color,
        ),
        4.verticalSpace,
        Text(
          StringSheet.sizeLabel(
            sizeInBytes != null
                ? StringSheet.sizeInMb(sizeInBytes!)
                : StringSheet.unknown,
          ),
          style: AppTextStyles.base.s12.ink400Color,
        ),
      ],
    );
  }

  Widget _buildTrailing() {
    final progress = downloadProgress;
    if (progress != null) {
      return SizedBox(
        width: 36.w,
        height: 36.w,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: progress > 0 ? progress : null,
              strokeWidth: 3,
              color: AppColors.primaryA500,
              backgroundColor: AppColors.primaryA200,
            ),
            Text(
              '${(progress * 100).round()}',
              style: AppTextStyles.base.s10.w600().primaryColor,
            ),
          ],
        ),
      );
    }

    if (isDownloaded) {
      return IconButton(
        onPressed: onDelete,
        icon: Icon(
          Icons.delete_outline,
          size: 22.w,
          color: AppColors.redA400,
        ),
        tooltip: StringSheet.deleteModelTooltip,
      );
    }

    return Material(
      color: AppColors.primaryA200,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        onTap: onDownload,
        borderRadius: BorderRadius.circular(10.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.download_rounded,
                size: 16.w,
                color: AppColors.primaryA500,
              ),
              4.horizontalSpace,
              Text(
                StringSheet.download,
                style: AppTextStyles.base.s12.w600().primaryColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
