import '../../../../core/constants/string_sheet.dart';

/// Các loại model AI mà SDK hỗ trợ.
enum AiModelType {
  carCorner(
    'CarCorner',
    StringSheet.carCornerName,
    StringSheet.carCornerShortName,
  ),
  carDamage(
    'CarDamage',
    StringSheet.carDamageName,
    StringSheet.carDamageShortName,
  ),
  carPart(
    'CarPart',
    StringSheet.carPartName,
    StringSheet.carPartShortName,
  ),
  licensePlate(
    'LicensePlate',
    StringSheet.licensePlateName,
    StringSheet.licensePlateShortName,
  );

  const AiModelType(
    this.apiValue,
    this.displayName,
    this.shortName,
  );

  /// Giá trị `modelType` gửi lên API.
  final String apiValue;

  /// Tên hiển thị đầy đủ trên UI.
  final String displayName;

  /// Tên ngắn gọn dùng cho tab / hint.
  final String shortName;

  static AiModelType fromApi(String value) {
    return AiModelType.values.firstWhere(
      (e) => e.apiValue == value,
      orElse: () => throw ArgumentError('Unknown model type: $value'),
    );
  }
}
