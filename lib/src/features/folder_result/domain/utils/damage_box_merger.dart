
import '../entity/inspection_result.dart';

/// Kết quả một bbox sau khi merge — sẵn sàng để vẽ.
class MergedDamageBox {
  const MergedDamageBox({
    required this.boxes,
    required this.label,
    required this.color,
  });

  /// `[x1, y1, x2, y2]` normalized 0..1.
  final List<double> boxes;

  /// Label hiển thị, các loại hư hỏng nối bằng ` / ` (vd `Trầy, xước / Móp, bẹp`).
  final String label;

  /// Màu hex của loại hư hỏng có priority cao nhất trong nhóm merge.
  final String? color;
}

abstract final class DamageBoxMerger {
  /// Ngưỡng IoU để coi hai bbox khác loại là cùng một vùng hư hỏng.
  static const double _crossClassIouThreshold = 0.6;

  /// Ngưỡng % bbox nhỏ nằm trong bbox lớn để coi là "containment".
  static const double _containmentRatioThreshold = 0.5;

  /// Bbox nhỏ phải chiếm tối thiểu tỉ lệ này so với bbox lớn mới được merge
  /// theo containment — tránh merge nhầm một object nhỏ nằm lọt bên trong.
  static const double _minSmallerToLargerAreaRatio = 0.4;

  /// Priority màu — số càng nhỏ càng ưu tiên hiển thị khi một bbox chứa
  /// nhiều loại hư hỏng. Slug không có trong bảng (vd `loose`, `missing`,
  /// hoặc annotation thủ công không rõ slug) mặc định priority thấp nhất.
  static const Map<String, int> _priorityBySlug = {
    'puncture': 1, // Thủng, rách
    'dent': 2, // Móp, bẹp
    'crack': 3, // Vỡ, nứt
    'scratch': 4, // Trầy, xước
    'loose': 5, // Long, rụng
    'missing': 6, // Mất
  };

  static const int _defaultPriority = 99;

  static List<MergedDamageBox> merge(List<PartMask> damageMasks) {
    var boxes = damageMasks
        .where((m) => m.boxes != null && m.boxes!.length >= 4)
        .map(_MergeBox.fromPartMask)
        .toList();
    if (boxes.isEmpty) return const [];

    var stable = false;
    while (!stable) {
      final beforeCount = boxes.length;
      boxes = _mergeSameSignature(boxes);
      boxes = _iterativeMerge(boxes, _shouldCrossClassMerge);
      stable = boxes.length == beforeCount;
    }

    return boxes.map((b) => b.toMergedDamageBox()).toList();
  }

  /// Step 1 (tổng quát) — group theo [_MergeBox.signature] (tổ hợp loại hư
  /// hỏng hiện có trong bbox), merge các bbox cùng signature có
  /// `Intersection Area > 0` (không quan tâm IoU/threshold).
  static List<_MergeBox> _mergeSameSignature(List<_MergeBox> boxes) {
    final bySignature = <String, List<_MergeBox>>{};
    for (final box in boxes) {
      bySignature.putIfAbsent(box.signature, () => []).add(box);
    }

    final result = <_MergeBox>[];
    for (final group in bySignature.values) {
      result.addAll(_iterativeMerge(group, _hasOverlap));
    }
    return result;
  }

  /// Merge lặp đi lặp lại các cặp bbox thoả [shouldMerge] cho đến khi không
  /// còn cặp nào thoả nữa (fixed point) — xử lý cả trường hợp bắc cầu kiểu
  /// "A overlap B, B overlap C ⇒ merge cả ba thành một".
  static List<_MergeBox> _iterativeMerge(
    List<_MergeBox> boxes,
    bool Function(_MergeBox a, _MergeBox b) shouldMerge,
  ) {
    var current = List<_MergeBox>.from(boxes);
    var mergedAny = true;
    while (mergedAny) {
      mergedAny = false;
      for (var i = 0; i < current.length && !mergedAny; i++) {
        for (var j = i + 1; j < current.length; j++) {
          if (!shouldMerge(current[i], current[j])) continue;
          final merged = current[i].mergeWith(current[j]);
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

  /// Step 1 condition — chỉ cần giao nhau một phần, không dùng IoU/threshold.
  static bool _hasOverlap(_MergeBox a, _MergeBox b) {
    final left = a.x1 > b.x1 ? a.x1 : b.x1;
    final top = a.y1 > b.y1 ? a.y1 : b.y1;
    final right = a.x2 < b.x2 ? a.x2 : b.x2;
    final bottom = a.y2 < b.y2 ? a.y2 : b.y2;
    return right > left && bottom > top;
  }

  /// Step 2 condition — `IoU > 0.6` HOẶC containment thoả cả 2 điều kiện.
  static bool _shouldCrossClassMerge(_MergeBox a, _MergeBox b) {
    final intersection = _intersectionArea(a, b);
    if (intersection <= 0) return false;

    final areaA = a.area;
    final areaB = b.area;

    final union = areaA + areaB - intersection;
    final iou = union > 0 ? intersection / union : 0;
    if (iou > _crossClassIouThreshold) return true;

    final smallerArea = areaA <= areaB ? areaA : areaB;
    final largerArea = areaA <= areaB ? areaB : areaA;
    if (smallerArea <= 0) return false;

    final containmentRatio = intersection / smallerArea;
    return containmentRatio > _containmentRatioThreshold &&
        smallerArea >= _minSmallerToLargerAreaRatio * largerArea;
  }

  static double _intersectionArea(_MergeBox a, _MergeBox b) {
    final left = a.x1 > b.x1 ? a.x1 : b.x1;
    final top = a.y1 > b.y1 ? a.y1 : b.y1;
    final right = a.x2 < b.x2 ? a.x2 : b.x2;
    final bottom = a.y2 < b.y2 ? a.y2 : b.y2;
    final width = right - left;
    final height = bottom - top;
    if (width <= 0 || height <= 0) return 0;
    return width * height;
  }

  static int _priorityOf(String? slug) =>
      _priorityBySlug[slug] ?? _defaultPriority;
}

/// Một thành phần loại hư hỏng đã gộp vào bbox (giữ để chọn label + màu).
class _DamageComponent {
  const _DamageComponent({required this.slug, required this.label, required this.color});

  final String? slug;
  final String label;
  final String? color;
}

/// Bbox trung gian trong lúc merge — mutable-free, `mergeWith` trả object mới.
class _MergeBox {
  const _MergeBox({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.components,
  });

  factory _MergeBox.fromPartMask(PartMask mask) {
    final b = mask.boxes!;
    final slug = mask.damageTypeSlug;
    final label = mask.vehiclePartName ?? '';
    return _MergeBox(
      x1: b[0],
      y1: b[1],
      x2: b[2],
      y2: b[3],
      components: [
        _DamageComponent(slug: slug, label: label, color: mask.vehicleColor),
      ],
    );
  }

  final double x1;
  final double y1;
  final double x2;
  final double y2;

  /// Toàn bộ loại hư hỏng đã gộp vào bbox này, thứ tự xuất hiện.
  final List<_DamageComponent> components;

  double get area {
    final width = x2 - x1;
    final height = y2 - y1;
    return width <= 0 || height <= 0 ? 0 : width * height;
  }

  String get signature {
    final keys = components.map((c) => c.slug ?? c.label).toSet().toList()
      ..sort();
    return keys.join('|');
  }

  _MergeBox mergeWith(_MergeBox other) {
    final mergedComponents = List<_DamageComponent>.from(components);
    for (final c in other.components) {
      final exists = mergedComponents.any((e) => e.label == c.label);
      if (!exists) mergedComponents.add(c);
    }
    return _MergeBox(
      x1: x1 < other.x1 ? x1 : other.x1,
      y1: y1 < other.y1 ? y1 : other.y1,
      x2: x2 > other.x2 ? x2 : other.x2,
      y2: y2 > other.y2 ? y2 : other.y2,
      components: mergedComponents,
    );
  }

  MergedDamageBox toMergedDamageBox() {
    final label = components
        .map((c) => c.label)
        .where((l) => l.isNotEmpty)
        .join(' / ');

    final sortedByPriority = [...components]..sort(
        (a, b) => DamageBoxMerger._priorityOf(a.slug)
            .compareTo(DamageBoxMerger._priorityOf(b.slug)),
      );
    final color = sortedByPriority
        .firstWhere(
          (c) => c.color != null && c.color!.isNotEmpty,
          orElse: () => const _DamageComponent(slug: null, label: '', color: null),
        )
        .color;

    return MergedDamageBox(
      boxes: [x1, y1, x2, y2],
      label: label,
      color: color,
    );
  }
}
