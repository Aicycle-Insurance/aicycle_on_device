import 'package:flutter/material.dart';

import '../../../../core/constants/string_sheet.dart';

/// Một loại tổn thất chọn được trên màn [AddDamageView].
class DamageTypeOption {
  const DamageTypeOption({
    required this.slug,
    required this.label,
    required this.icon,
  });

  final String slug;
  final String label;
  final IconData icon;
}

/// Danh sách cố định loại tổn thất — slug dùng khi gửi BE.
abstract final class DamageTypeOptions {
  static const List<DamageTypeOption> all = [
    DamageTypeOption(
      slug: 'scratch',
      label: StringSheet.damageTypeScratch,
      icon: Icons.show_chart_rounded,
    ),
    DamageTypeOption(
      slug: 'dent',
      label: StringSheet.damageTypeDent,
      icon: Icons.grid_view_rounded,
    ),
    DamageTypeOption(
      slug: 'crack',
      label: StringSheet.damageTypeCrack,
      icon: Icons.hub_outlined,
    ),
    DamageTypeOption(
      slug: 'loose',
      label: StringSheet.damageTypeLoose,
      icon: Icons.open_in_full_rounded,
    ),
    DamageTypeOption(
      slug: 'puncture',
      label: StringSheet.damageTypePuncture,
      icon: Icons.photo_size_select_actual_outlined,
    ),
    DamageTypeOption(
      slug: 'missing',
      label: StringSheet.damageTypeMissing,
      icon: Icons.visibility_off_outlined,
    ),
  ];

  static DamageTypeOption? bySlug(String? slug) {
    if (slug == null) return null;
    for (final o in all) {
      if (o.slug == slug) return o;
    }
    return null;
  }
}
