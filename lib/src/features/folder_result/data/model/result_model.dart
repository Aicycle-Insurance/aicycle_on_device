// Model cho kết quả giám định trả về từ endpoint
// `insurance/v2/claimfolders/{sessionId}/external-segment-result`.
//
// Response là một mảng các bộ phận xe (vehicle part), mỗi phần tử gồm thông
// tin bộ phận, danh sách hư hỏng, ảnh và phương án sửa chữa.

import '../../domain/entity/inspection_result.dart';

/// Một bộ phận xe trong kết quả giám định.
class VehiclePartModel {
  const VehiclePartModel({
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
  final List<DamageModel> damages;
  final List<ResultImageModel> images;
  final String? repairPlan;
  final num? paintPrice;
  final num? dentedPrice;
  final String? paintLevel;
  final List<int>? imageIdsBuyMe;
  final String? paintPercentageExternal;
  final String? dentedLevelExternal;
  final String? punctureLevelExternal;

  factory VehiclePartModel.fromJson(Map<String, dynamic> json) {
    return VehiclePartModel(
      vehiclePartExcelId: json['vehiclePartExcelId'] as String?,
      vehiclePartName: json['vehiclePartName'] as String?,
      vehiclePartDirectionSlug: json['vehiclePartDirectionSlug'] as String?,
      vehiclePartDirectionName: json['vehiclePartDirectionName'] as String?,
      paintPercentage: (json['paintPercentage'] as num?)?.toDouble(),
      dentedLevel: json['dentedLevel'] as String?,
      punctureLevel: json['punctureLevel'] as String?,
      damages: (json['damages'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DamageModel.fromJson)
          .toList(),
      images: (json['images'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ResultImageModel.fromJson)
          .toList(),
      repairPlan: json['repairPlan'] as String?,
      paintPrice: json['paintPrice'] as num?,
      dentedPrice: json['dentedPrice'] as num?,
      paintLevel: json['paintLevel'] as String?,
      imageIdsBuyMe: (json['imageIdsBuyMe'] as List<dynamic>?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      paintPercentageExternal: json['paintPercentageExternal'] as String?,
      dentedLevelExternal: json['dentedLevelExternal'] as String?,
      punctureLevelExternal: json['punctureLevelExternal'] as String?,
    );
  }

  /// [masksByImageId] — map imageId → PartMask list để merge khi convert,
  /// mặc định empty (không áp mask).
  VehiclePart toEntity([Map<int, List<PartMask>> masksByImageId = const {}]) {
    return VehiclePart(
      vehiclePartExcelId: vehiclePartExcelId,
      vehiclePartName: vehiclePartName,
      vehiclePartDirectionSlug: vehiclePartDirectionSlug,
      vehiclePartDirectionName: vehiclePartDirectionName,
      paintPercentage: paintPercentage,
      dentedLevel: dentedLevel,
      punctureLevel: punctureLevel,
      damages: damages.map((e) => e.toEntity()).toList(),
      images: images
          .map((img) => img.toEntity(masksByImageId[img.imageId]))
          .toList(),
      repairPlan: repairPlan,
      paintPrice: paintPrice,
      dentedPrice: dentedPrice,
      paintLevel: paintLevel,
      imageIdsBuyMe: imageIdsBuyMe,
      paintPercentageExternal: paintPercentageExternal,
      dentedLevelExternal: dentedLevelExternal,
      punctureLevelExternal: punctureLevelExternal,
    );
  }
}

/// Một hư hỏng trên bộ phận (vd Xước, Móp).
class DamageModel {
  const DamageModel({
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

  factory DamageModel.fromJson(Map<String, dynamic> json) {
    return DamageModel(
      damageTypeSlug: json['damageTypeSlug'] as String?,
      damageTypeName: json['damageTypeName'] as String?,
      damagePercentage: (json['damagePercentage'] as num?)?.toDouble(),
      damageTypeColor: json['damageTypeColor'] as String?,
      paintPosition: json['paintPosition'] as String?,
    );
  }

  Damage toEntity() {
    return Damage(
      damageTypeSlug: damageTypeSlug,
      damageTypeName: damageTypeName,
      damagePercentage: damagePercentage,
      damageTypeColor: damageTypeColor,
      paintPosition: paintPosition,
    );
  }
}

/// Ảnh kết quả của bộ phận, kèm thông tin nhận diện và mask hư hỏng.
class ResultImageModel {
  const ResultImageModel({
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
  final ImageExtraInfoModel? extraInfo;
  final String? errorType;
  final String? errorNote;
  final String? uploadedTime;
  final double? timeProcess;
  final num? timeAppUpload;
  final String? imageUrl;
  final String? imageDrawUrl;
  final List<DamageMaskModel> damageImageInfo;
  final List<PartMaskModel> partsMasks;

  factory ResultImageModel.fromJson(Map<String, dynamic> json) {
    final extra = json['extraInfo'];
    return ResultImageModel(
      imageId: json['imageId'] as int?,
      claimId: json['claimId'] as int?,
      resolution: (json['resolution'] as List<dynamic>?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      filePath: json['filePath'] as String?,
      directionEngineSlug: json['directionEngineSlug'] as String?,
      positionEngineSlug: json['positionEngineSlug'] as String?,
      directionSlug: json['directionSlug'] as String?,
      positionSlug: json['positionSlug'] as String?,
      extraInfo: extra is Map<String, dynamic>
          ? ImageExtraInfoModel.fromJson(extra)
          : null,
      errorType: json['errorType'] as String?,
      errorNote: json['errorNote'] as String?,
      uploadedTime: json['uploadedTime'] as String?,
      timeProcess: (json['timeProcess'] as num?)?.toDouble(),
      timeAppUpload: json['timeAppUpload'] as num?,
      imageUrl: json['imageUrl'] as String?,
      imageDrawUrl: json['imageDrawUrl'] as String?,
      damageImageInfo: (json['damageImageInfo'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(DamageMaskModel.fromJson)
          .toList(),
      partsMasks: (json['partsMasks'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PartMaskModel.fromJson)
          .toList(),
    );
  }

  /// [overrideMasks] — khi được truyền vào, dùng thay cho [partsMasks] của model
  /// (dùng khi repository merge dữ liệu từ endpoint `/images`).
  ResultImage toEntity([List<PartMask>? overrideMasks]) {
    return ResultImage(
      imageId: imageId,
      claimId: claimId,
      resolution: resolution,
      filePath: filePath,
      directionEngineSlug: directionEngineSlug,
      positionEngineSlug: positionEngineSlug,
      directionSlug: directionSlug,
      positionSlug: positionSlug,
      extraInfo: extraInfo?.toEntity(),
      errorType: errorType,
      errorNote: errorNote,
      uploadedTime: uploadedTime,
      timeProcess: timeProcess,
      timeAppUpload: timeAppUpload,
      imageUrl: imageUrl,
      imageDrawUrl: imageDrawUrl,
      damageImageInfo: damageImageInfo.map((e) => e.toEntity()).toList(),
      partsMasks: overrideMasks ?? partsMasks.map((e) => e.toEntity()).toList(),
    );
  }
}

/// Thông tin xe trích từ ảnh (hãng, model, màu, biển số).
class ImageExtraInfoModel {
  const ImageExtraInfoModel({
    this.carCompany,
    this.carModel,
    this.carColor,
    this.plateNumber,
  });

  final String? carCompany;
  final String? carModel;
  final List<int>? carColor;
  final String? plateNumber;

  factory ImageExtraInfoModel.fromJson(Map<String, dynamic> json) {
    return ImageExtraInfoModel(
      carCompany: json['carCompany'] as String?,
      carModel: json['carModel'] as String?,
      carColor: (json['carColor'] as List<dynamic>?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      plateNumber: json['plateNumber'] as String?,
    );
  }

  ImageExtraInfo toEntity() {
    return ImageExtraInfo(
      carCompany: carCompany,
      carModel: carModel,
      carColor: carColor,
      plateNumber: plateNumber,
    );
  }
}

/// `claimfolders/{sessionId}/images`.
class PartMaskModel {
  const PartMaskModel({
    this.maskUrl,
    this.masksPath,
    this.boxes,
    this.vehiclePartName,
    this.vehicleColor,
    this.scores,
    this.isPart,
  });

  final String? maskUrl;
  final String? masksPath;
  final List<double>? boxes;
  final String? vehiclePartName;
  final String? vehicleColor;
  final num? scores;
  final bool? isPart;

  factory PartMaskModel.fromJson(Map<String, dynamic> json) {
    return PartMaskModel(
      maskUrl: json['maskUrl'] as String?,
      masksPath: json['masksPath'] as String?,
      boxes: (json['boxes'] as List<dynamic>?)
          ?.whereType<num>()
          .map((e) => e.toDouble())
          .toList(),
      vehiclePartName: json['vehiclePartName'] as String?,
      vehicleColor: json['vehicleColor'] as String?,
      scores: json['scores'] as num?,
      isPart: json['isPart'] is bool
          ? json['isPart'] as bool
          : json['isPart']?.toString().contains('true'),
    );
  }

  PartMask toEntity() {
    return PartMask(
      maskUrl: maskUrl,
      masksPath: masksPath,
      boxes: boxes,
      vehiclePartName: vehiclePartName,
      vehicleColor: vehicleColor,
      scores: scores,
      isPart: isPart,
    );
  }
}

/// Một phần tử response của endpoint `claimfolders/{sessionId}/images`,
/// gắn liền với một [ResultImage] cụ thể qua [imageId].
class PartViewImageModel {
  const PartViewImageModel({
    this.imageId,
    this.url,
    this.imageSize,
    this.directionName,
    this.partsMasks = const [],
  });

  final int? imageId;
  final String? url;
  final List<int>? imageSize;
  final String? directionName;
  final List<PartMaskModel> partsMasks;

  factory PartViewImageModel.fromJson(Map<String, dynamic> json) {
    return PartViewImageModel(
      imageId: (json['imageId'] as num?)?.toInt(),
      url: json['url'] as String?,
      imageSize: (json['imageSize'] as List<dynamic>?)
          ?.whereType<num>()
          .map((e) => e.toInt())
          .toList(),
      directionName: json['directionName'] as String?,
      partsMasks: (json['partsMasks'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PartMaskModel.fromJson)
          .toList(),
    );
  }
}

/// Mask của một hư hỏng trên ảnh (ảnh PNG overlay).
class DamageMaskModel {
  const DamageMaskModel({
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

  factory DamageMaskModel.fromJson(Map<String, dynamic> json) {
    return DamageMaskModel(
      maskUrl: json['maskUrl'] as String?,
      damageTypeSlug: json['damageTypeSlug'] as String?,
      damageTypeName: json['damageTypeName'] as String?,
      damagePercentage: (json['damagePercentage'] as num?)?.toDouble(),
      damageTypeColor: json['damageTypeColor'] as String?,
    );
  }

  DamageMask toEntity() {
    return DamageMask(
      maskUrl: maskUrl,
      damageTypeSlug: damageTypeSlug,
      damageTypeName: damageTypeName,
      damagePercentage: damagePercentage,
      damageTypeColor: damageTypeColor,
    );
  }
}
