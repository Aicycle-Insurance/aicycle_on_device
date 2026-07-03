/// Bản ghi tổn thất người dùng xác nhận — payload gửi BE sau này.
class DamageAnnotationDraft {
  const DamageAnnotationDraft({
    required this.imageId,
    required this.normalizedPosition,
    required this.vehiclePartName,
    required this.damageTypeSlug,
    required this.damageTypeName,
    this.logicalPixelPosition,
  });

  final int imageId;
  final List<double> normalizedPosition;
  final List<int>? logicalPixelPosition;
  final String vehiclePartName;
  final String damageTypeSlug;
  final String damageTypeName;

  Map<String, dynamic> toJson() => {
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
