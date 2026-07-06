/// Bản ghi tổn thất người dùng xác nhận — payload gửi BE sau này.
class DamageAnnotationDraft {
  const DamageAnnotationDraft({
    required this.localId,
    required this.imageId,
    required this.normalizedPosition,
    required this.vehiclePartName,
    required this.damageTypeSlug,
    required this.damageTypeName,
    this.logicalPixelPosition,
  });

  final String localId;
  final int imageId;
  final List<double> normalizedPosition;
  final List<int>? logicalPixelPosition;
  final String vehiclePartName;
  final String damageTypeSlug;
  final String damageTypeName;

  static int _idCounter = 0;

  /// Sinh id local duy nhất khi tạo annotation mới.
  static String newLocalId() {
    _idCounter += 1;
    return 'damage_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'imageId': imageId,
        'x': normalizedPosition[0],
        'y': normalizedPosition[1],
        if (logicalPixelPosition != null) 'pixelX': logicalPixelPosition![0],
        if (logicalPixelPosition != null) 'pixelY': logicalPixelPosition![1],
        'vehiclePartName': vehiclePartName,
        'damageTypeSlug': damageTypeSlug,
        'damageTypeName': damageTypeName,
      };
}
