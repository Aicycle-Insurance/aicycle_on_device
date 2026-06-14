/// Output từ model classify (YOLO classify).
class ClassifyOutput {
  final double fps;
  final double cameraFps;
  final double processingTimeMs;
  final Classification classification;

  const ClassifyOutput({
    required this.fps,
    required this.cameraFps,
    required this.processingTimeMs,
    required this.classification,
  });

  factory ClassifyOutput.fromJson(Map<String, dynamic> json) {
    return ClassifyOutput(
      fps: (json['fps'] as num).toDouble(),
      cameraFps: (json['cameraFps'] as num).toDouble(),
      processingTimeMs: (json['processingTimeMs'] as num).toDouble(),
      classification: Classification.fromJson(
        Map<String, dynamic>.from(json['classification'] as Map),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': 'classify',
        'fps': fps,
        'cameraFps': cameraFps,
        'processingTimeMs': processingTimeMs,
        'classification': classification.toJson(),
      };

  @override
  String toString() =>
      'ClassifyOutput(fps: $fps, top1: ${classification.top1}, '
      'confidence: ${classification.top1Confidence})';
}

class Classification {
  final String top1;
  final double top1Confidence;
  final List<ClassifyCandidate> top5;

  const Classification({
    required this.top1,
    required this.top1Confidence,
    required this.top5,
  });

  factory Classification.fromJson(Map<String, dynamic> json) {
    return Classification(
      top1: json['top1'] as String,
      top1Confidence: (json['top1Confidence'] as num).toDouble(),
      top5: (json['top5'] as List<dynamic>)
          .map((e) =>
              ClassifyCandidate.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'top1': top1,
        'top1Confidence': top1Confidence,
        'top5': top5.map((e) => e.toJson()).toList(),
      };
}

class ClassifyCandidate {
  final String name;
  final double confidence;

  const ClassifyCandidate({
    required this.name,
    required this.confidence,
  });

  factory ClassifyCandidate.fromJson(Map<String, dynamic> json) {
    return ClassifyCandidate(
      name: json['name'] as String,
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'confidence': confidence,
      };

  @override
  String toString() =>
      'ClassifyCandidate(name: $name, confidence: $confidence)';
}
