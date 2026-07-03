import 'dart:ui';

import '../../domain/entity/inspection_result.dart';

/// Kết quả tap vào mask trên ảnh kết quả — dùng lưu state trước khi gửi BE.
class MaskTapResult {
  const MaskTapResult({
    required this.imageId,
    required this.mask,
    required this.normalizedPosition,
    required this.displayPosition,
    this.logicalPixelPosition,
  });

  /// Ảnh chứa vị trí tap — FK đồng bộ với BE.
  final int imageId;

  /// Mask bộ phận được tap.
  final PartMask mask;

  /// Tọa độ normalized `[x, y]` trong khoảng 0..1 — cùng hệ với [PartMask.boxes].
  final List<double> normalizedPosition;

  /// Vị trí tap trong không gian pixel của ảnh display (để đặt nút overlay).
  final Offset displayPosition;

  /// Tọa độ pixel gốc theo [ResultImage.resolution] của BE, nếu có.
  final List<int>? logicalPixelPosition;
}
