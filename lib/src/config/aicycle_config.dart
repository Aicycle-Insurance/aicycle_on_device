import 'package:flutter/material.dart';

enum AiCycleEnvironment { develop, stage, production }

enum AiCycleOrg { aicycle, partner, others }

class AICycleConfig {
  /// Thông tin xe
  final CarInformation carInformation;

  /// Cấu hình chung cho SDK
  final GeneralConfig generalConfig;

  /// Cấu hình cho model
  final ModelConfig modelConfig;

  /// Cấu hình hiển thị
  final DisplayConfig displayConfig;

  AICycleConfig({
    required this.generalConfig,
    required this.modelConfig,
    required this.carInformation,
    this.displayConfig = const DisplayConfig(),
  });
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
  /// Token API
  final String apiToken;

  /// ID của hồ sơ
  final String documentId;

  /// Tên của hồ sơ
  final String? documentName;

  /// Môi trường
  final AiCycleEnvironment environment;

  /// Cho phép log hay không
  final bool loggingEnabled;

  /// Tổ chức sử dụng SDK
  final AiCycleOrg organization;

  GeneralConfig({
    required this.apiToken,
    required this.documentId,
    required this.organization,
    this.environment = AiCycleEnvironment.develop,
    this.documentName,
    this.loggingEnabled = false,
  });
}

class ModelConfig {
  /// Confidence threshold của model (giá trị từ 0.0 đến 1.0)
  final double? confidenceThreshold;

  /// IOU threshold của model (giá trị từ 0.0 đến 1.0)
  final double? iouThreshold;

  ModelConfig({
    this.confidenceThreshold,
    this.iouThreshold,
  })  : assert(
          confidenceThreshold == null ||
              (confidenceThreshold >= 0.0 && confidenceThreshold <= 1.0),
          'confidenceThreshold phải nằm trong khoảng từ 0.0 đến 1.0',
        ),
        assert(
          iouThreshold == null || (iouThreshold >= 0.0 && iouThreshold <= 1.0),
          'iouThreshold phải nằm trong khoảng từ 0.0 đến 1.0',
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
