// Entity tầng domain cho kết quả giám định.
//
// Response của fetchResult là một mảng [VehiclePart].

/// Một bộ phận xe trong kết quả giám định.
class VehiclePart {
  const VehiclePart({
    this.vehiclePartExcelId,
    this.vehiclePartName,
    this.vehiclePartDirectionSlug,
    this.vehiclePartDirectionName,
    this.paintPercentage,
    this.dentedLevel,
    this.punctureLevel,
    this.damages = const [],
    this.images = const [],
    this.repairPlan,
    this.paintPrice,
    this.dentedPrice,
    this.paintLevel,
    this.imageIdsBuyMe,
    this.paintPercentageExternal,
    this.dentedLevelExternal,
    this.punctureLevelExternal,
  });

  final String? vehiclePartExcelId;
  final String? vehiclePartName;
  final String? vehiclePartDirectionSlug;
  final String? vehiclePartDirectionName;
  final double? paintPercentage;
  final String? dentedLevel;
  final String? punctureLevel;
  final List<Damage> damages;
  final List<ResultImage> images;
  final String? repairPlan;
  final num? paintPrice;
  final num? dentedPrice;
  final String? paintLevel;
  final List<int>? imageIdsBuyMe;
  final String? paintPercentageExternal;
  final String? dentedLevelExternal;
  final String? punctureLevelExternal;

  /// `true` nếu bộ phận có ít nhất một hư hỏng.
  bool get hasDamage => damages.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'vehiclePartExcelId': vehiclePartExcelId,
      'vehiclePartName': vehiclePartName,
      'vehiclePartDirectionSlug': vehiclePartDirectionSlug,
      'vehiclePartDirectionName': vehiclePartDirectionName,
      'paintPercentage': paintPercentage,
      'dentedLevel': dentedLevel,
      'punctureLevel': punctureLevel,
      'damages': damages.map((e) => e.toJson()).toList(),
      'images': images.map((e) => e.toJson()).toList(),
      'repairPlan': repairPlan,
      'paintPrice': paintPrice,
      'dentedPrice': dentedPrice,
      'paintLevel': paintLevel,
      'imageIdsBuyMe': imageIdsBuyMe,
      'paintPercentageExternal': paintPercentageExternal,
      'dentedLevelExternal': dentedLevelExternal,
      'punctureLevelExternal': punctureLevelExternal,
    };
  }
}

/// Một hư hỏng trên bộ phận (vd Xước, Móp).
class Damage {
  const Damage({
    this.damageTypeSlug,
    this.damageTypeName,
    this.damagePercentage,
    this.damageTypeColor,
    this.paintPosition,
  });

  final String? damageTypeSlug;
  final String? damageTypeName;
  final double? damagePercentage;
  final String? damageTypeColor;
  final String? paintPosition;

  Map<String, dynamic> toJson() {
    return {
      'damageTypeSlug': damageTypeSlug,
      'damageTypeName': damageTypeName,
      'damagePercentage': damagePercentage,
      'damageTypeColor': damageTypeColor,
      'paintPosition': paintPosition,
    };
  }
}

/// Ảnh kết quả của bộ phận, kèm thông tin nhận diện và mask hư hỏng.
class ResultImage {
  const ResultImage({
    this.imageId,
    this.claimId,
    this.resolution,
    this.filePath,
    this.directionEngineSlug,
    this.positionEngineSlug,
    this.directionSlug,
    this.positionSlug,
    this.extraInfo,
    this.errorType,
    this.errorNote,
    this.uploadedTime,
    this.timeProcess,
    this.timeAppUpload,
    this.imageUrl,
    this.imageDrawUrl,
    this.damageImageInfo = const [],
    this.partsMasks = const [],
  });

  final int? imageId;
  final int? claimId;
  final List<int>? resolution;
  final String? filePath;
  final String? directionEngineSlug;
  final String? positionEngineSlug;
  final String? directionSlug;
  final String? positionSlug;
  final ImageExtraInfo? extraInfo;
  final String? errorType;
  final String? errorNote;
  final String? uploadedTime;
  final double? timeProcess;
  final num? timeAppUpload;
  final String? imageUrl;
  final String? imageDrawUrl;
  final List<DamageMask> damageImageInfo;

  final List<PartMask> partsMasks;

  Map<String, dynamic> toJson() {
    return {
      'imageId': imageId,
      'claimId': claimId,
      'resolution': resolution,
      'filePath': filePath,
      'directionEngineSlug': directionEngineSlug,
      'positionEngineSlug': positionEngineSlug,
      'directionSlug': directionSlug,
      'positionSlug': positionSlug,
      'extraInfo': extraInfo?.toJson(),
      'errorType': errorType,
      'errorNote': errorNote,
      'uploadedTime': uploadedTime,
      'timeProcess': timeProcess,
      'timeAppUpload': timeAppUpload,
      'imageUrl': imageUrl,
      'imageDrawUrl': imageDrawUrl,
      'damageImageInfo': damageImageInfo.map((e) => e.toJson()).toList(),
      'partsMasks': partsMasks.map((e) => e.toJson()).toList(),
    };
  }
}

/// Thông tin xe trích từ ảnh (hãng, model, màu, biển số).
class ImageExtraInfo {
  const ImageExtraInfo({
    this.carCompany,
    this.carModel,
    this.carColor,
    this.plateNumber,
  });

  final String? carCompany;
  final String? carModel;
  final List<int>? carColor;
  final String? plateNumber;

  Map<String, dynamic> toJson() {
    return {
      'carCompany': carCompany,
      'carModel': carModel,
      'carColor': carColor,
      'plateNumber': plateNumber,
    };
  }
}

/// Mask của một bộ phận xe (segmentation), lấy từ endpoint
/// `claimfolders/{sessionId}/images`.
///
/// [boxes] là `[x1, y1, x2, y2]` normalized 0..1 theo `imageSize` gốc của BE
/// — dùng chung với [ResultImage.resolution] để tính vị trí hiển thị.
class PartMask {
  const PartMask({
    this.maskUrl,
    this.masksPath,
    this.boxes,
    this.vehiclePartName,
    this.vehicleColor,
    this.scores,
    this.isPart,
    this.damageTypeSlug,
  });

  final String? maskUrl;
  final String? masksPath;
  final List<double>? boxes;
  final String? vehiclePartName;
  final String? vehicleColor;
  final num? scores;
  final bool? isPart;

  /// Slug loại hư hỏng (vd `scratch`, `dent`, `crack`...), `null` với mask
  /// bộ phận xe (`isPart == true`). Dùng để group/merge bbox và chọn màu
  /// theo priority — xem [DamageBoxMerger].
  final String? damageTypeSlug;

  Map<String, dynamic> toJson() {
    return {
      'maskUrl': maskUrl,
      'masksPath': masksPath,
      'boxes': boxes,
      'vehiclePartName': vehiclePartName,
      'vehicleColor': vehicleColor,
      'scores': scores,
      'isPart': isPart,
      'damageTypeSlug': damageTypeSlug,
    };
  }
}

/// Mask của một hư hỏng trên ảnh (ảnh PNG overlay).
class DamageMask {
  const DamageMask({
    this.maskUrl,
    this.damageTypeSlug,
    this.damageTypeName,
    this.damagePercentage,
    this.damageTypeColor,
  });

  final String? maskUrl;
  final String? damageTypeSlug;
  final String? damageTypeName;
  final double? damagePercentage;
  final String? damageTypeColor;

  Map<String, dynamic> toJson() {
    return {
      'maskUrl': maskUrl,
      'damageTypeSlug': damageTypeSlug,
      'damageTypeName': damageTypeName,
      'damagePercentage': damagePercentage,
      'damageTypeColor': damageTypeColor,
    };
  }
}
