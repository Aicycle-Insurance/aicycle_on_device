import 'package:flutter/material.dart';

import '../../../core/constants/string_sheet.dart';
import '../../../core/di/injection.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/screen_utils.dart';
import '../data/model/downloaded_model_info.dart';
import '../domain/entity/ai_model_type.dart';
import 'controller/model_manager_controller.dart';
import 'widgets/model_type_tab_view.dart';

/// Màn hình quản lý model AI tải về.
///
/// Mỗi loại model (CarCorner, CarDamage, CarPart) hiển thị trong một tab
/// riêng. User phải tải và chọn ít nhất 1 model cho mỗi loại mới được
/// chuyển sang màn camera.
class ModelManagerScreen extends StatefulWidget {
  const ModelManagerScreen({
    super.key,
    this.onContinue,
    this.showBackButton = false,
  });

  /// Gọi khi user bấm "Tiếp tục" với model đã chọn cho từng loại.
  final void Function(Map<AiModelType, DownloadedModelInfo> selectedModels)?
      onContinue;

  final bool showBackButton;

  @override
  State<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends State<ModelManagerScreen>
    with SingleTickerProviderStateMixin {
  late final ModelManagerController _controller;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: AiModelType.values.length,
      vsync: this,
    );
    _controller = ModelManagerController(sl.aiModelRepository)
      ..onActionError = _showError
      ..init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: AppTextStyles.baseWhite.s14),
        backgroundColor: AppColors.redA500,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmDeleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(
          StringSheet.deleteAllDialogTitle,
          style: AppTextStyles.base.s16.w600().ink500Color,
        ),
        content: Text(
          StringSheet.deleteAllDialogContent,
          style: AppTextStyles.base.s14.ink400Color,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              StringSheet.cancel,
              style: AppTextStyles.base.s14.ink400Color,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              StringSheet.deleteAll,
              style: AppTextStyles.base.s14.w600().redA500Color,
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      _controller.deleteAllModels();
    }
  }

  @override
  Widget build(BuildContext context) {
    ScreenUtil.init(context);
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: _buildAppBar(),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Column(
          children: [
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  for (final type in AiModelType.values)
                    ModelTypeTabView(type: type, controller: _controller),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => _buildBottomBar(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.white,
      surfaceTintColor: AppColors.transparent,
      elevation: 0,
      centerTitle: true,
      automaticallyImplyLeading: widget.showBackButton,
      iconTheme: const IconThemeData(color: AppColors.inkA500),
      title: Text(
        StringSheet.modelManagerTitle,
        style: AppTextStyles.base.s18.w600().ink500Color,
      ),
      actions: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            if (!_controller.hasDownloadedModels) {
              return const SizedBox.shrink();
            }
            if (_controller.isDeletingAll) {
              return Padding(
                padding: EdgeInsets.only(right: 16.w),
                child: SizedBox(
                  width: 20.w,
                  height: 20.w,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.redA500,
                  ),
                ),
              );
            }
            return IconButton(
              onPressed: _confirmDeleteAll,
              tooltip: StringSheet.deleteAllTooltip,
              icon: const Icon(
                Icons.delete_sweep_outlined,
                color: AppColors.redA500,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: AppColors.white,
      child: TabBar(
        controller: _tabController,
        labelColor: AppColors.primaryA500,
        unselectedLabelColor: AppColors.inkA400,
        labelStyle: AppTextStyles.base.s14.w600(),
        unselectedLabelStyle: AppTextStyles.base.s14,
        indicatorColor: AppColors.primaryA500,
        indicatorWeight: 2.5,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: AppColors.divider,
        tabs: [
          for (final type in AiModelType.values)
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_controller.isTypeReady(type)) ...[
                    Icon(
                      Icons.check_circle,
                      size: 14.w,
                      color: AppColors.greenA500,
                    ),
                    4.horizontalSpace,
                  ],
                  Flexible(
                    child: Text(type.shortName, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final canContinue = _controller.canContinue;
    final missingTypes = AiModelType.values
        .where((type) => !_controller.isTypeReady(type))
        .map((type) => type.shortName)
        .join(', ');

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 12.h),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.inkA500.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!canContinue) ...[
              Text(
                StringSheet.missingTypes(missingTypes),
                style: AppTextStyles.base.s12.ink400Color,
                textAlign: TextAlign.center,
              ),
              8.verticalSpace,
            ],
            SizedBox(
              width: double.infinity,
              height: 48.h,
              child: FilledButton(
                onPressed: canContinue
                    ? () => widget.onContinue?.call(_controller.selectedModels)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryA500,
                  disabledBackgroundColor: AppColors.inactive,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
                child: Text(
                  StringSheet.continueButton,
                  style: AppTextStyles.baseWhite.s16.w600(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
