import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/model/detection_output.dart';

class BoundingBoxOverlay extends StatelessWidget {
  const BoundingBoxOverlay({super.key, required this.detections});

  final List<DetectionResult> detections;

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) return const SizedBox.expand();
    return CustomPaint(
      painter: _BoundingBoxPainter(detections),
      size: Size.infinite,
    );
  }
}

class _BoundingBoxPainter extends CustomPainter {
  _BoundingBoxPainter(this.detections);

  final List<DetectionResult> detections;

  static const _colors = {
    'Móp, bẹp(thụng)': Color(0xFFEF5350),
    'Vỡ, nứt': Color(0xFFFF9800),
    'Thủng, rách': Color(0xFFFFEB3B),
    'Trầy, xước': Color(0xFF42A5F5),
  };

  static const _defaultColor = Color(0xFFAB47BC);

  @override
  void paint(Canvas canvas, Size size) {
    // Camera frames are landscape; Flutter canvas is portrait (portrait-locked app).
    // UI uses RotatedBox(quarterTurns: 1) = 90° clockwise.
    // Transform: translate(W, 0) + rotate(π/2) maps landscape coords → portrait screen.
    // Result: screen_x = (1 - norm_y) * W,  screen_y = norm_x * H
    canvas.save();
    canvas.translate(size.width, 0);
    canvas.rotate(math.pi / 2);

    // After rotation, the local canvas is landscape: width=size.height, height=size.width
    final lw = size.height;
    final lh = size.width;

    final boxPaint = Paint()..style = PaintingStyle.stroke..strokeWidth = 2;

    for (final d in detections) {
      final color = _colors[d.className] ?? _defaultColor;
      boxPaint.color = color;

      final rect = Rect.fromLTRB(
        d.normalizedBox.left * lw,
        d.normalizedBox.top * lh,
        d.normalizedBox.right * lw,
        d.normalizedBox.bottom * lh,
      );

      canvas.drawRect(rect, boxPaint);

      _drawLabel(canvas, d, rect, color);
    }

    canvas.restore();
  }

  void _drawLabel(Canvas canvas, DetectionResult d, Rect rect, Color color) {
    final label =
        '${d.className} ${(d.confidence * 100).toStringAsFixed(0)}%';
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padding = 3.0;
    final bgRect = Rect.fromLTWH(
      rect.left,
      rect.top - tp.height - padding * 2,
      tp.width + padding * 2,
      tp.height + padding * 2,
    );

    canvas.drawRect(bgRect, Paint()..color = color);
    tp.paint(canvas, Offset(rect.left + padding, bgRect.top + padding));
  }

  @override
  bool shouldRepaint(_BoundingBoxPainter old) =>
      old.detections != detections;
}
