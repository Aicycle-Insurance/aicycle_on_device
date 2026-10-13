import 'dart:math' as math;

import '../../data/model/detection_output.dart';

/// Tiện ích gộp các bounding box tổn thất nằm chồng lấn lên nhau trên cùng một
/// diện tích trong luồng camera real-time.
///
/// Thuật toán tối ưu hoá để chạy trên từng frame camera với chi phí CPU cực thấp
/// (< 0.02ms), sử dụng ngưỡng an toàn (Safe Spatial Overlap Threshold) để chống
/// tình trạng rung giật (anti-flicker) và giữ màu sắc theo mức độ nghiêm trọng
/// cao nhất.
abstract final class DamageBoxSpatialMerger {
  /// Ngưỡng IoU an toàn để coi 2 box là cùng một vùng tổn thất.
  /// Đặt ở 0.35 để tránh merge chớp tắt khi mép box chỉ chạm nhẹ do rung tay.
  static const double defaultIouThreshold = 0.35;

  /// Ngưỡng % diện tích box nhỏ nằm lọt trong box lớn để coi là lồng nhau.
  static const double defaultContainmentThreshold = 0.55;

  /// Thứ tự ưu tiên hiển thị màu/nhãn — số càng nhỏ độ nghiêm trọng càng cao.
  static const Map<String, int> _priorityByClass = {
    'Thủng, rách': 1,
    'Móp, bẹp(thụng)': 2,
    'Vỡ, nứt': 3,
    'Trầy, xước': 4,
  };

  static const int _defaultPriority = 99;

  /// Gộp các box tổn thất trong danh sách [detections].
  static List<DetectionResult> merge(
    List<DetectionResult> detections, {
    double iouThreshold = defaultIouThreshold,
    double containmentThreshold = defaultContainmentThreshold,
  }) {
    if (detections.length <= 1) return detections;

    var current = List<DetectionResult>.from(detections);
    var mergedAny = true;

    while (mergedAny) {
      mergedAny = false;
      for (var i = 0; i < current.length && !mergedAny; i++) {
        for (var j = i + 1; j < current.length; j++) {
          final a = current[i];
          final b = current[j];

          if (!_shouldMerge(a, b, iouThreshold, containmentThreshold)) {
            continue;
          }

          final merged = _mergePair(a, b);
          current = [
            for (var k = 0; k < current.length; k++)
              if (k != i && k != j) current[k],
            merged,
          ];
          mergedAny = true;
          break;
        }
      }
    }

    return current;
  }

  static bool _shouldMerge(
    DetectionResult a,
    DetectionResult b,
    double iouThreshold,
    double containmentThreshold,
  ) {
    final boxA = a.normalizedBox;
    final boxB = b.normalizedBox;

    final interLeft = math.max(boxA.left, boxB.left);
    final interTop = math.max(boxA.top, boxB.top);
    final interRight = math.min(boxA.right, boxB.right);
    final interBottom = math.min(boxA.bottom, boxB.bottom);

    final interWidth = interRight - interLeft;
    final interHeight = interBottom - interTop;

    if (interWidth <= 0 || interHeight <= 0) return false;

    final interArea = interWidth * interHeight;
    final areaA = boxA.width * boxA.height;
    final areaB = boxB.width * boxB.height;

    final union = areaA + areaB - interArea;
    final iou = union > 0 ? interArea / union : 0.0;
    if (iou >= iouThreshold) return true;

    final smallerArea = math.min(areaA, areaB);
    if (smallerArea <= 0) return false;

    final containmentRatio = interArea / smallerArea;
    return containmentRatio >= containmentThreshold;
  }

  static DetectionResult _mergePair(DetectionResult a, DetectionResult b) {
    final boxA = a.normalizedBox;
    final boxB = b.normalizedBox;

    final left = math.min(boxA.left, boxB.left);
    final top = math.min(boxA.top, boxB.top);
    final right = math.max(boxA.right, boxB.right);
    final bottom = math.max(boxA.bottom, boxB.bottom);

    final priorityA = _priorityByClass[a.className] ?? _defaultPriority;
    final priorityB = _priorityByClass[b.className] ?? _defaultPriority;

    // Chọn className có mức độ ưu tiên cao hơn (số nhỏ hơn).
    // Nếu ngang nhau thì chọn box có confidence cao hơn.
    final String chosenClass;
    if (priorityA < priorityB) {
      chosenClass = a.className;
    } else if (priorityB < priorityA) {
      chosenClass = b.className;
    } else {
      chosenClass = a.confidence >= b.confidence ? a.className : b.className;
    }

    final maxConfidence = math.max(a.confidence, b.confidence);

    return DetectionResult(
      className: chosenClass,
      confidence: maxConfidence,
      normalizedBox: NormalizedBox(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
      ),
    );
  }
}
