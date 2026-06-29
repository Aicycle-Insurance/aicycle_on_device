import 'package:flutter/material.dart';

enum AiCycleEnvironment { develop, stage, production }

enum AiCycleOrg { aicycle, vbi, others }

class AICycleConfig {
  /// Thông tin xe
  final CarInformation carInformation;

  /// Cấu hình chung cho SDK
  final GeneralConfig generalConfig;

  /// Cấu hình cho model
  final ModelConfig modelConfig;

  /// Cấu hình hiển thị
  final DisplayConfig displayConfig;

  /// Cấu hình validate (vd: có bắt buộc chụp ảnh toàn cảnh 4 góc không)
  final ValidateConfig validateConfig;

  /// Cấu hình riêng cho VBI (bắt buộc nếu organization là VBI)
  final VBIConfig? vbiConfig;

  AICycleConfig({
    required this.generalConfig,
    required this.modelConfig,
    required this.carInformation,
    this.displayConfig = const DisplayConfig(),
    this.validateConfig = const ValidateConfig(),
    this.vbiConfig,
  }) : assert(
          generalConfig.organization != AiCycleOrg.vbi || vbiConfig != null,
          'vbiConfig is required when organization is vbi',
        );
}

class CarInformation {
  /// Hãng xe (ví dụ: "toyota")
  final String companyName;

  /// Dòng xe/Hiệu xe (ví dụ: "vios")
  final String modelName;

  /// Năm sản xuất (ví dụ: 2022)
  final int? manufacturingYear;

  /// Phiên bản xe (ví dụ: "1.5C")
  final String vehicleVersionName;

  /// Biển số xe (ví dụ: "30A12345")
  final String licensePlate;

  /// Loại xe (ví dụ: "pickup")
  final String? vehicleType;

  /// Màu xe (nếu có)
  /// Dạng hex #RRGGBB
  final String? color;

  /// ID của garage
  final String garageId;

  /// ID của brand
  final String vehicleBrandId;

  CarInformation({
    this.companyName = '',
    this.modelName = '',
    this.vehicleBrandId = '',
    this.garageId = '',
    this.manufacturingYear,
    this.vehicleVersionName = '',
    this.licensePlate = '',
    this.vehicleType,
    this.color,
  });
}

class GeneralConfig {
  /// AICycle Token API (liên hệ AICycle để được cấp token)
  final String apiToken;

  /// ID của hồ sơ (so_id_hs)
  final String documentId;

  /// Tên của hồ sơ
  final String? documentName;

  /// Môi trường
  final AiCycleEnvironment environment;

  /// Cho phép log hay không
  final bool loggingEnabled;

  /// Tổ chức sử dụng SDK
  final AiCycleOrg organization;

  /// Có lưu lại ảnh đã chụp vào gallery không
  final bool savePhotoAfterShot;

  /// API Endpoint của AICycle trong môi trường On-Premise của đối tác (nếu có)
  /// Ví dụ: https://example.com
  final String? aicBaseUrl;

  GeneralConfig({
    required this.apiToken,
    required this.documentId,
    required this.organization,
    this.environment = AiCycleEnvironment.develop,
    this.documentName,
    this.loggingEnabled = false,
    this.savePhotoAfterShot = true,
    this.aicBaseUrl,
  })  : assert(
          aicBaseUrl == null || aicBaseUrl.isNotEmpty,
          'aicBaseUrl phải khác rỗng nếu được cung cấp',
        ),
        assert(
          organization != AiCycleOrg.vbi ||
              (aicBaseUrl != null && aicBaseUrl.isNotEmpty),
          'aicBaseUrl là bắt buộc và phải khác rỗng với đối tác VBI',
        );
}

class ValidateConfig {
  /// Có bắt buộc chụp ảnh toàn cảnh cả 4 góc không?
  final bool require4AnglePanoramicPhotos;

  const ValidateConfig({
    this.require4AnglePanoramicPhotos = false,
  });
}

class ModelConfig {
  /// Confidence threshold của model car part detection (giá trị từ 0.0 đến 1.0)
  final double carPartConfThreshold;

  /// IOU threshold của model car part detection (giá trị từ 0.0 đến 1.0)
  final double carPartIouThreshold;

  /// Confidence threshold của model car corner classification (giá trị từ 0.0 đến 1.0)
  final double carCornerConfThreshold;

  /// Confidence threshold của model car damage detection (giá trị từ 0.0 đến 1.0)
  final double carDamageConfThreshold;

  /// IOU threshold của model detection (giá trị từ 0.0 đến 1.0)
  final double carDamageIouThreshold;

  /// Confidence threshold của model license plate OCR (giá trị từ 0.0 đến 1.0)
  final double licensePlateConfThreshold;

  ModelConfig({
    this.carPartConfThreshold = 0.5,
    this.carPartIouThreshold = 0.45,
    this.carCornerConfThreshold = 0.3,
    this.carDamageConfThreshold = 0.3,
    this.carDamageIouThreshold = 0.45,
    this.licensePlateConfThreshold = 0.5,
  })  : assert(
          carPartConfThreshold >= 0.0 && carPartConfThreshold <= 1.0,
          'carPartConfThreshold phải nằm trong khoảng từ 0.0 đến 1.0',
        ),
        assert(
          carPartIouThreshold >= 0.0 && carPartIouThreshold <= 1.0,
          'carPartIouThreshold phải nằm trong khoảng từ 0.0 đến 1.0',
        ),
        assert(
          carCornerConfThreshold >= 0.0 && carCornerConfThreshold <= 1.0,
          'carCornerConfThreshold phải nằm trong khoảng từ 0.0 đến 1.0',
        ),
        assert(
          carDamageConfThreshold >= 0.0 && carDamageConfThreshold <= 1.0,
          'carDamageConfThreshold phải nằm trong khoảng từ 0.0 đến 1.0',
        ),
        assert(
          carDamageIouThreshold >= 0.0 && carDamageIouThreshold <= 1.0,
          'carDamageIouThreshold phải nằm trong khoảng từ 0.0 đến 1.0',
        ),
        assert(
          licensePlateConfThreshold >= 0.0 && licensePlateConfThreshold <= 1.0,
          'licensePlateConfThreshold phải nằm trong khoảng từ 0.0 đến 1.0',
        );
}

class DisplayConfig {
  /// Custom loading widget
  final Widget? loadingWidget;

  /// Hiển thị nút back
  final bool showBackButton;

  const DisplayConfig({
    this.loadingWidget,
    this.showBackButton = false,
  });
}

class VBIConfig {
  /// Ví dụ: v1, v2
  final String apiVersionCode;

  /// API upload ảnh của hệ thống VBI
  /// Ví dụ: https://uat-api.example.com
  final String apiUploadBaseUrl;
  final String authorityId;
  final String signatureKey;
  final String externalSessionId;
  final String jobId;
  final String maHangMuc;
  final String tenHangMuc;
  final String departmentId;
  final String userId;
  final String maTVV;
  final String source;

  VBIConfig({
    required this.apiVersionCode,
    required this.apiUploadBaseUrl,
    required this.authorityId,
    required this.signatureKey,
    required this.externalSessionId,
    required this.jobId,
    required this.maHangMuc,
    required this.tenHangMuc,
    required this.departmentId,
    required this.userId,
    required this.maTVV,
    required this.source,
  });
}
