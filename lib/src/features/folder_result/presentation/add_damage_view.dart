import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/string_sheet.dart';
import '../../../core/themes/app_colors.dart';
import '../../../core/themes/app_textstyle.dart';
import '../../../core/utils/screen_utils.dart';
import 'models/add_damage_view_result.dart';
import 'models/damage_annotation_draft.dart';
import 'models/damage_type_option.dart';
import 'models/mask_tap_result.dart';
import 'widgets/damage_type_grid.dart';

enum AddDamageViewMode { add, edit }

class AddDamageView extends StatefulWidget {
  const AddDamageView.add({
    super.key,
    required this.tapResult,
    this.imageUrl,
  })  : mode = AddDamageViewMode.add,
        initialDraft = null;

  const AddDamageView.edit({
    super.key,
    required this.initialDraft,
    this.imageUrl,
  })  : mode = AddDamageViewMode.edit,
        tapResult = null;

  final AddDamageViewMode mode;
  final MaskTapResult? tapResult;
  final DamageAnnotationDraft? initialDraft;
  final String? imageUrl;

  @override
  State<AddDamageView> createState() => _AddDamageViewState();
}

class _AddDamageViewState extends State<AddDamageView> {
  late String? _selectedDamageSlug;

  bool get _isEdit => widget.mode == AddDamageViewMode.edit;

  @override
  void initState() {
    super.initState();
    _selectedDamageSlug = _isEdit ? widget.initialDraft!.damageTypeSlug : null;
  }

  String get _partName {
    if (_isEdit) {
      return widget.initialDraft!.vehiclePartName;
    }
    return widget.tapResult!.mask.vehiclePartName ?? StringSheet.unknown;
  }

  DamageAnnotationDraft _buildDraftFromForm(DamageTypeOption option) {
    if (_isEdit) {
      final draft = widget.initialDraft!;
      return DamageAnnotationDraft(
        localId: draft.localId,
        imageId: draft.imageId,
        normalizedPosition: draft.normalizedPosition,
        logicalPixelPosition: draft.logicalPixelPosition,
        vehiclePartName: draft.vehiclePartName,
        damageTypeSlug: option.slug,
        damageTypeName: option.label,
      );
    }

    final tap = widget.tapResult!;
    return DamageAnnotationDraft(
      localId: DamageAnnotationDraft.newLocalId(),
      imageId: tap.imageId,
      normalizedPosition: tap.normalizedPosition,
      logicalPixelPosition: tap.logicalPixelPosition,
      vehiclePartName: _partName,
      damageTypeSlug: option.slug,
      damageTypeName: option.label,
    );
  }

  void _save() {
    final slug = _selectedDamageSlug;
    if (slug == null) return;

    final option = DamageTypeOptions.bySlug(slug);
    if (option == null) return;

    Navigator.of(context).pop(
      AddDamageViewSaved(_buildDraftFromForm(option)),
    );
  }

  void _delete() {
    Navigator.of(context).pop(
      AddDamageViewDeleted(widget.initialDraft!.localId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final landscapeMq = mq.copyWith(
      size: Size(mq.size.height, mq.size.width),
      padding: EdgeInsets.fromLTRB(
        mq.padding.bottom,
        mq.padding.left,
        mq.padding.top,
        mq.padding.right,
      ),
      viewPadding: EdgeInsets.fromLTRB(
        mq.viewPadding.bottom,
        mq.viewPadding.left,
        mq.viewPadding.top,
        mq.viewPadding.right,
      ),
      viewInsets: EdgeInsets.fromLTRB(
        mq.viewInsets.bottom,
        mq.viewInsets.left,
        mq.viewInsets.top,
        mq.viewInsets.right,
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: AppColors.bottombarBackground,
          body: MediaQuery(
            data: landscapeMq.copyWith(
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
            ),
            child: RotatedBox(
              quarterTurns: 1,
              child: Builder(
                builder: (innerCtx) {
                  ScreenUtil.init(
                    innerCtx,
                    designSize: ScreenUtil.landscapeDesignSize,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(innerCtx),
                      Expanded(child: _buildBody(innerCtx)),
                      _buildFooter(innerCtx),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final title =
        _isEdit ? StringSheet.editDamage : StringSheet.addDamage;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.inkA500.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 10.h),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: AppTextStyles.base.s18.w700().copyWith(
                    color: AppColors.inkA500,
                  ),
            ),
            10.horizontalSpace,
            _PartChip(label: _partName),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.all(4.r),
                child: Icon(
                  Icons.close_rounded,
                  size: 22.r,
                  color: AppColors.inkA500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 11,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  StringSheet.damageTypeSection,
                  style: AppTextStyles.base.s14.w600().copyWith(
                        color: AppColors.inkA500,
                      ),
                ),
                10.verticalSpace,
                Expanded(
                  child: DamageTypeGrid(
                    selectedSlug: _selectedDamageSlug,
                    onSelected: (option) {
                      setState(() => _selectedDamageSlug = option.slug);
                    },
                  ),
                ),
              ],
            ),
          ),
          16.horizontalSpace,
          Expanded(
            flex: 9,
            child: _buildImagePreview(),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    final url = widget.imageUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: ColoredBox(
        color: AppColors.placeholder,
        child: url == null || url.isEmpty
            ? Center(
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: 40.r,
                  color: AppColors.inkA300,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 40.r,
                    color: AppColors.inkA300,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final canSave = _selectedDamageSlug != null;

    if (!_isEdit) {
      return Padding(
        padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 12.h),
        child: SizedBox(
          width: double.infinity,
          height: 44.h,
          child: FilledButton(
            onPressed: canSave ? _save : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryA600,
              disabledBackgroundColor: AppColors.primaryA300,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            child: Text(
              StringSheet.saveChanges,
              style: AppTextStyles.base.s14.w600().copyWith(
                    color: AppColors.white,
                  ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(14.w, 0, 14.w, 12.h),
      child: SizedBox(
        height: 44.h,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.redA500,
                  side: const BorderSide(color: AppColors.redA300),
                  backgroundColor: AppColors.redA200,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                ),
                icon: Icon(Icons.delete_outline_rounded, size: 18.r),
                label: Text(
                  StringSheet.deleteDamage,
                  style: AppTextStyles.base.s14.w600().copyWith(
                        color: AppColors.redA500,
                      ),
                ),
              ),
            ),
            12.horizontalSpace,
            Expanded(
              child: FilledButton(
                onPressed: canSave ? _save : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryA600,
                  disabledBackgroundColor: AppColors.primaryA300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                ),
                child: Text(
                  StringSheet.saveChanges,
                  style: AppTextStyles.base.s14.w600().copyWith(
                        color: AppColors.white,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip hiển thị tên bộ phận xe đã tap.
class _PartChip extends StatelessWidget {
  const _PartChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.partChip,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: AppColors.partChipBorder, width: 1),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 11.w, vertical: 4.h),
        child: Text(
          label,
          style: AppTextStyles.base.s16.w600().copyWith(
                color: AppColors.primaryA600,
              ),
        ),
      ),
    );
  }
}
