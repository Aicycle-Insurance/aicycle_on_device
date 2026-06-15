/*
Nóc xe
Viền nóc (mui)
Pa vô lê
Kính chắn gió trước
Ca pô trước
Ca lăng
Lốp phụ sau xe
Ba đờ sốc trước
Lưới ba đờ sốc
Ốp ba đờ sốc trước
Lô gô
Đèn phản quang ba đờ sốc sau
Cốp sau / Cửa hậu
Ba đờ sốc sau
Ốp ba đờ sốc sau
Kính chắn gió sau
Đèn gầm
Ốp đèn gầm
Cụm đèn trước
Mặt gương (kính) chiếu hậu
Vỏ gương (kính) chiếu hậu
Chân gương (kính) chiếu hậu
Đèn xi nhan trên gương chiếu hậu
Trụ kính trước
Tai (vè trước) xe
Ốp Tai (vè trước) xe
Đèn xi nhan ba đ sốc
Ốp đèn xi nhan ba đ sốc
Đèn hậu
Kính chết góc cửa
Kính hông
Hông (vè sau) xe / thùng xe
Trụ kính sau
Đèn hậu trên cốp sau
La giăng (Mâm xe)
Lốp (vỏ) xe
Tay mở cửa
Kính cánh cửa
Cánh cửa
Trụ kính cánh cửa
Ốp hông (vè sau) xe / thùng xe
Nẹp cốp sau
Bậc cánh cửa
Nẹp ca pô trước
Biển số xe
Đèn đi ban ngày
Ốp cánh cửa
Ốp viền gầm cản trước
Ốp ba đờ sốc sau LR
Ốp ba đờ sốc trước LR
Ốp cánh cửa FB
Kính chết góc cửa trước
Tên dòng xe
Nẹp ca lăng
Nẹp kính cánh cửa
Nẹp cánh cửa
Nắp thùng xe
Nắp thùng xe LR
Nắp thùng xe sau
Kính nắp thùng xe sau
Kính nắp thùng xe LR
Trụ cánh cửa
Nắp bình xăng
Thùng xe tải
Nẹp cụm đèn trước
Ba đờ sốc sau LR
Ốp ba đờ sốc sau trên
Ốp đèn hậu
Ốp mạ bạc ba đờ sốc trước
Ốp mạ bạc ba đờ sốc sau
Ốp pa vô lê
Nẹp mạ cản trước
Nẹp mạ cản sau
Đèn xi nhan ba đờ sốc sau
Ốp trụ kính hông
Ốp cụm đèn trước
Đèn hậu trên cốp sau LR
*/

/// Output từ model segment (YOLO segment).
class SegmentationOutput {
  final double fps;
  final double cameraFps;
  final double processingTimeMs;
  final List<SegmentDetection> detections;

  const SegmentationOutput({
    required this.fps,
    required this.cameraFps,
    required this.processingTimeMs,
    required this.detections,
  });

  factory SegmentationOutput.fromJson(Map<String, dynamic> json) {
    return SegmentationOutput(
      fps: (json['fps'] as num).toDouble(),
      cameraFps: (json['cameraFps'] as num).toDouble(),
      processingTimeMs: (json['processingTimeMs'] as num).toDouble(),
      detections: (json['detections'] as List<dynamic>)
          .map((e) =>
              SegmentDetection.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': 'segment',
        'fps': fps,
        'cameraFps': cameraFps,
        'processingTimeMs': processingTimeMs,
        'detections': detections.map((e) => e.toJson()).toList(),
      };

  @override
  String toString() =>
      'SegmentationOutput(fps: $fps, detections: ${detections.length})';
}

class SegmentDetection {
  final String className;
  final double confidence;
  final NormalizedBox normalizedBox;

  const SegmentDetection({
    required this.className,
    required this.confidence,
    required this.normalizedBox,
  });

  factory SegmentDetection.fromJson(Map<String, dynamic> json) {
    return SegmentDetection(
      className: (json['className'] as String?) ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      normalizedBox: NormalizedBox.fromJson(
        Map<String, dynamic>.from(json['normalizedBox'] as Map),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'className': className,
        'confidence': confidence,
        'normalizedBox': normalizedBox.toJson(),
      };

  @override
  String toString() =>
      'SegmentDetection(className: $className, confidence: $confidence)';
}

class NormalizedBox {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const NormalizedBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  factory NormalizedBox.fromJson(Map<String, dynamic> json) {
    return NormalizedBox(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      right: (json['right'] as num).toDouble(),
      bottom: (json['bottom'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      };

  @override
  String toString() =>
      'NormalizedBox(left: $left, top: $top, right: $right, bottom: $bottom)';
}
