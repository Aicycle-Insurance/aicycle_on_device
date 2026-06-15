import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/screen_utils.dart';

/// Ring chia làm 4 cung độc lập, tương ứng 4 góc xe.
/// Index (chiều kim đồng hồ từ trên):
///   0 = phải - trước
///   1 = phải - sau
///   2 = trái - sau
///   3 = trái - trước
class CarProgressRing extends StatelessWidget {
  const CarProgressRing({
    super.key,
    this.activeIndex,
    this.completedIndices = const {},
    this.size,
    this.activeColor = const Color(0xFFFFD53E),
    this.completedColor = const Color(0xFF01D6A8),
    this.inactiveColor = const Color(0xFFCCCCCC),
  });

  final int? activeIndex;
  final Set<int> completedIndices;
  final double? size;
  final Color activeColor;
  final Color completedColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final ringSize = size ?? 67.r;
    return SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(ringSize, ringSize),
            painter: _CarRingPainter(
              activeIndex: activeIndex,
              completedIndices: completedIndices,
              activeColor: activeColor,
              completedColor: completedColor,
              inactiveColor: inactiveColor,
            ),
          ),
          SizedBox(
            width: ringSize * 0.7,
            height: ringSize * 0.7,
            child: RotatedBox(
              quarterTurns: 1,
              child: Image.asset(
                AppAssets.car,
                fit: BoxFit.contain,
                package: 'aicycle_on_device',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CarRingPainter extends CustomPainter {
  _CarRingPainter({
    required this.activeIndex,
    required this.completedIndices,
    required this.activeColor,
    required this.completedColor,
    required this.inactiveColor,
  });

  final int? activeIndex;
  final Set<int> completedIndices;
  final Color activeColor;
  final Color completedColor;
  final Color inactiveColor;

  static const int _count = 4;
  static const double _gapDeg = 5.0;
  static const double _gapRad = _gapDeg * pi / 180;
  static const double _sweep = (2 * pi - _count * _gapRad) / _count;

  // Góc bắt đầu của cung thứ i (canvas: 0=phải, chiều kim đồng hồ)
  static double _start(int i) => -pi / 2 + i * (pi / 2) + _gapRad / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.width / 2;
    final ringW = outer * 0.15;
    final inner = outer - ringW - 2;
    final track = outer - ringW / 2;

    // 1. Vòng tối bên trong
    canvas.drawCircle(center, inner,
        Paint()..color = Color(0xFFACADB9).withValues(alpha: 0.65));
    canvas.drawCircle(
      center,
      inner,
      Paint()
        ..color = Colors.transparent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    // 2. Vẽ 4 cung nền xám
    final grayPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringW
      ..strokeCap = StrokeCap.butt;

    for (int i = 0; i < _count; i++) {
      grayPaint.color = inactiveColor;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: track),
        _start(i),
        _sweep,
        false,
        grayPaint,
      );
    }

    // 4. Vẽ cung màu (active / completed) phủ lên grid
    final colorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringW
      ..strokeCap = StrokeCap.butt;

    for (int i = 0; i < _count; i++) {
      final isActive = i == activeIndex;
      final isDone = completedIndices.contains(i);
      if (!isActive && !isDone) continue;

      colorPaint.color = isActive ? activeColor : completedColor;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: track),
        _start(i),
        _sweep,
        false,
        colorPaint,
      );
    }

    // 6. Đường phân cách giữa các cung
    _drawGaps(canvas, center, outer, inner);
  }

  void _drawGaps(Canvas canvas, Offset center, double outer, double inner) {
    final paint = Paint()
      ..color = Colors.transparent
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    for (int i = 0; i < _count; i++) {
      // Vẽ tại điểm bắt đầu của mỗi cung (tức là gap trước cung đó)
      final angle = _start(i) - _gapRad / 2;
      final cosA = cos(angle);
      final sinA = sin(angle);
      canvas.drawLine(
        Offset(center.dx + (inner - 1) * cosA, center.dy + (inner - 1) * sinA),
        Offset(center.dx + (outer + 1) * cosA, center.dy + (outer + 1) * sinA),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CarRingPainter old) =>
      old.activeIndex != activeIndex ||
      old.completedIndices != completedIndices ||
      old.activeColor != activeColor ||
      old.completedColor != completedColor ||
      old.inactiveColor != inactiveColor;
}
