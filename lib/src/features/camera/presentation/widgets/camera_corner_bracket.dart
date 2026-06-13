import 'package:flutter/material.dart';

/// Single L-shaped corner bracket drawn as a stroked path with a smooth
/// rounded corner (quarter-circle arc). By default renders the top-left
/// corner (horizontal arm goes right, vertical arm goes down). Flip with
/// [flipX] / [flipY] to get the other three corners.
class CameraCornerBracket extends StatelessWidget {
  const CameraCornerBracket({
    super.key,
    this.armLength = 28.0,
    this.cornerRadius = 10.0,
    this.strokeWidth = 4.0,
    this.color = const Color(0xFFFFD600),
    this.flipX = false,
    this.flipY = false,
  });

  final double armLength;
  final double cornerRadius;
  final double strokeWidth;
  final Color color;
  final bool flipX;
  final bool flipY;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scaleX: flipX ? -1.0 : 1.0,
      scaleY: flipY ? -1.0 : 1.0,
      child: CustomPaint(
        size: Size(armLength, armLength),
        painter: _CornerPainter(
          cornerRadius: cornerRadius,
          strokeWidth: strokeWidth,
          color: color,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  const _CornerPainter({
    required this.cornerRadius,
    required this.strokeWidth,
    required this.color,
  });

  final double cornerRadius;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final half = strokeWidth / 2;
    final r = cornerRadius;

    // Draws the top-left bracket:
    //   horizontal arm  →  quarter-circle arc  →  vertical arm ↓
    final path = Path()
      ..moveTo(size.width, half)
      ..lineTo(half + r, half)
      ..arcToPoint(
        Offset(half, half + r),
        radius: Radius.circular(r),
        clockwise: false,
      )
      ..lineTo(half, size.height);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) =>
      old.cornerRadius != cornerRadius ||
      old.strokeWidth != strokeWidth ||
      old.color != color;
}

/// Positions four [CameraCornerBracket] widgets at the corners of a
/// rectangular camera frame. Wrap around [MultiTaskYOLOView] or any
/// camera preview widget.
class CameraFrameCorners extends StatelessWidget {
  const CameraFrameCorners({
    super.key,
    this.armLength = 32.0,
    this.cornerRadius = 16.0,
    this.strokeWidth = 4.0,
    this.color = const Color(0xFFFFD600),
    this.padding = 16.0,
  });

  final double armLength;
  final double cornerRadius;
  final double strokeWidth;
  final Color color;

  /// Distance from the edge of [child] to each bracket corner.
  final double padding;

  @override
  Widget build(BuildContext context) {
    CameraCornerBracket bracket(bool fx, bool fy) => CameraCornerBracket(
          armLength: armLength,
          cornerRadius: cornerRadius,
          strokeWidth: strokeWidth,
          color: color,
          flipX: fx,
          flipY: fy,
        );

    return Stack(
      children: [
        // top-left
        Positioned(top: padding, left: padding, child: bracket(false, false)),
        // top-right
        Positioned(top: padding, right: padding, child: bracket(true, false)),
        // bottom-left
        Positioned(bottom: padding, left: padding, child: bracket(false, true)),
        // bottom-right
        Positioned(bottom: padding, right: padding, child: bracket(true, true)),
      ],
    );
  }
}
