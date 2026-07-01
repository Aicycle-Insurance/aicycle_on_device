import 'dart:ui';

/// Fit ảnh vào khung [maxWidth × maxHeight], giữ aspect ratio (contain).
///
/// Trả về kích thước **display** trên UI — dùng chung cho ảnh gốc và mask overlay.
Size fitImageContain({
  required Size logicalSize,
  required double maxWidth,
  required double maxHeight,
}) {
  if (logicalSize.width <= 0 || logicalSize.height <= 0) {
    return Size.zero;
  }
  if (maxWidth <= 0 || maxHeight <= 0) {
    return Size.zero;
  }

  final imageRatio = logicalSize.width / logicalSize.height;
  final containerRatio = maxWidth / maxHeight;

  if (containerRatio < imageRatio) {
    final width = maxWidth;
    final height = width / imageRatio;
    return Size(width, height);
  } else {
    final height = maxHeight;
    final width = height * imageRatio;
    return Size(width, height);
  }
}

/// Hệ số scale từ logical → display (dùng khi convert pixel thô từ BE).
double scaleFactor(Size logicalSize, Size displaySize) {
  if (logicalSize.width <= 0) return 0;
  return displaySize.width / logicalSize.width;
}

/// Lấy [Size] logical từ `resolution` BE `[width, height]`.
Size? logicalSizeFromResolution(List<int>? resolution) {
  if (resolution == null || resolution.length < 2) return null;
  final width = resolution[0];
  final height = resolution[1];
  if (width <= 0 || height <= 0) return null;
  return Size(width.toDouble(), height.toDouble());
}

/// Map bbox normalized `[x1, y1, x2, y2]` sang rect display pixel.
Rect maskDisplayRect(List<double> boxes, double imWidth, double imHeight) {
  return Rect.fromLTRB(
    boxes[0] * imWidth,
    boxes[1] * imHeight,
    boxes[2] * imWidth,
    boxes[3] * imHeight,
  );
}
