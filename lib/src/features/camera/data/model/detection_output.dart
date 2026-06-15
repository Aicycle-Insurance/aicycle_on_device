import 'sementation_output.dart';
/*
Móp, bẹp(thụng)
Vỡ, nứt
Thủng, rách
Trầy, xước
*/

/// Output từ model detect (YOLO detect).
class DetectionOutput {
  final double fps;
  final double cameraFps;
  final double processingTimeMs;
  final List<DetectionResult> detections;

  const DetectionOutput({
    required this.fps,
    required this.cameraFps,
    required this.processingTimeMs,
    required this.detections,
  });

  factory DetectionOutput.fromJson(Map<String, dynamic> json) {
    return DetectionOutput(
      fps: (json['fps'] as num).toDouble(),
      cameraFps: (json['cameraFps'] as num).toDouble(),
      processingTimeMs: (json['processingTimeMs'] as num).toDouble(),
      detections: (json['detections'] as List<dynamic>)
          .map((e) =>
              DetectionResult.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': 'detect',
        'fps': fps,
        'cameraFps': cameraFps,
        'processingTimeMs': processingTimeMs,
        'detections': detections.map((e) => e.toJson()).toList(),
      };

  @override
  String toString() =>
      'DetectionOutput(fps: $fps, detections: ${detections.length})';
}

class DetectionResult {
  final String className;
  final double confidence;
  final NormalizedBox normalizedBox;

  const DetectionResult({
    required this.className,
    required this.confidence,
    required this.normalizedBox,
  });

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
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
      'DetectionResult(className: $className, confidence: $confidence)';
}
