import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/string_sheet.dart';

/// Một loại tổn thất chọn được trên màn [AddDamageView].
class DamageTypeOption {
  const DamageTypeOption({
    required this.slug,
    required this.label,
    required this.iconAsset,
  });

  final String slug;
  final String label;
  final String iconAsset;
}

/// Danh sách cố định loại tổn thất — slug dùng khi gửi BE.
abstract final class DamageTypeOptions {
  static const List<DamageTypeOption> all = [
    DamageTypeOption(
      slug: 'scratch',
      label: StringSheet.damageTypeScratch,
      iconAsset: AppAssets.scratch,
    ),
    DamageTypeOption(
      slug: 'dent',
      label: StringSheet.damageTypeDent,
      iconAsset: AppAssets.dent,
    ),
    DamageTypeOption(
      slug: 'crack',
      label: StringSheet.damageTypeCrack,
      iconAsset: AppAssets.crack,
    ),
    DamageTypeOption(
      slug: 'loose',
      label: StringSheet.damageTypeLoose,
      iconAsset: AppAssets.loose,
    ),
    DamageTypeOption(
      slug: 'puncture',
      label: StringSheet.damageTypePuncture,
      iconAsset: AppAssets.puncture,
    ),
    DamageTypeOption(
      slug: 'missing',
      label: StringSheet.damageTypeMissing,
      iconAsset: AppAssets.missing,
    ),
  ];

  static const Map<String, String> _beSlugByUiSlug = {
    'scratch': 'tray-xuoc-g06jcx',
    'dent': 'mop-bep-jtep4m',
    'crack': 'vo-nut-E6BNTw',
    'loose': 'long-rung-i2rm16',
    'puncture': 'thung-rach-EcfqAl',
    'missing': 'mat-4iytj1',
  };

  static DamageTypeOption? bySlug(String? slug) {
    if (slug == null) return null;
    for (final o in all) {
      if (o.slug == slug) return o;
    }
    return null;
  }

  static String? toBeSlug(String? uiSlug) {
    if (uiSlug == null) return null;
    return _beSlugByUiSlug[uiSlug];
  }
}
