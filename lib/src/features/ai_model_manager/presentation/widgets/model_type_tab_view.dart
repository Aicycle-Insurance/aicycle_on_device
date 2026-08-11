import 'package:flutter/material.dart';

import '../../../../core/constants/string_sheet.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';
import '../../domain/entity/ai_model_type.dart';
import '../controller/model_manager_controller.dart';
import 'model_card.dart';

/// Nội dung một tab: danh sách model của một loại
/// (CarCorner / CarDamage / CarPart).
class ModelTypeTabView extends StatelessWidget {
  const ModelTypeTabView({
    super.key,
    required this.type,
    required this.controller,
  });

  final AiModelType type;
  final ModelManagerController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.stateOf(type);

    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryA500),
      );
    }

    if (state.error != null) {
      return _buildError(state.error!);
    }

    return RefreshIndicator(
      color: AppColors.primaryA500,
      onRefresh: () => controller.fetchModels(type),
      child: state.models.isEmpty
          ? _buildEmpty()
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.all(16.w),
              children: [
                _buildSummary(state.models.length),
                12.verticalSpace,
                for (final model in state.models)
                  ModelCard(
                    model: model,
                    isSelected: controller.isSelected(model),
                    isDownloaded: controller.isDownloaded(model),
                    downloadProgress: controller.downloadProgressOf(model),
                    sizeInBytes: controller.sizeOf(model),
                    onDownload: () => controller.downloadModel(model),
                    onDelete: () => controller.deleteModel(model),
                    onSelect: () => controller.selectModel(model),
                  ),
              ],
            ),
    );
  }

  Widget _buildSummary(int count) {
    final selectedVersion = controller.selectedVersionOf(type);
    return Row(
      children: [
        Expanded(
          child: Text(
            StringSheet.versionCount(count),
            style: AppTextStyles.base.s12.ink400Color,
          ),
        ),
        if (selectedVersion != null)
          Row(
            children: [
              Icon(Icons.check_circle, size: 14.w, color: AppColors.greenA500),
              4.horizontalSpace,
              Text(
                StringSheet.selectedVersion(selectedVersion),
                style: AppTextStyles.base.s12.w500().setColor(
                      AppColors.greenA500,
                    ),
              ),
            ],
          )
        else
          Text(
            StringSheet.notSelected,
            style: AppTextStyles.base.s12.ink400Color,
          ),
      ],
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40.w, color: AppColors.redA400),
            12.verticalSpace,
            Text(
              message,
              style: AppTextStyles.base.s14.ink400Color,
              textAlign: TextAlign.center,
            ),
            16.verticalSpace,
            TextButton(
              onPressed: () => controller.fetchModels(type),
              child: Text(
                StringSheet.retry,
                style: AppTextStyles.base.s14.w600().primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: 120.h),
        Center(
          child: Text(
            StringSheet.emptyModels,
            style: AppTextStyles.base.s14.ink400Color,
          ),
        ),
      ],
    );
  }
}
