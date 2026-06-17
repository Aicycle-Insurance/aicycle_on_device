import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/model/sementation_output.dart';

/// Vẽ nhãn tên bộ phận lên trên các vùng segment.
///
/// Chỉ hiển thị các bộ phận nằm trong [_partDisplayNames]; tên thô từ model
/// được ánh xạ sang tên hiển thị rút gọn. Bộ phận không nằm trong danh sách
/// sẽ không được vẽ nhãn.
class CarPartLabelOverlay extends StatelessWidget {
  const CarPartLabelOverlay({super.key, required this.detections});

  final List<SegmentDetection> detections;

  /// Ánh xạ tên thô (model segment) → tên hiển thị rút gọn.
  /// Chỉ những bộ phận có trong map này mới được hiển thị nhãn.
  static const Map<String, String> _partDisplayNames = {
    'Ba đờ sốc trước': 'Ba đờ sốc trước',
    'Ba đờ sốc sau': 'Ba đờ sốc sau',
    'Cánh cửa': 'Cánh cửa',
    'Ca pô trước': 'Capo',
    'Tai (vè trước) xe': 'Vè trước',
    'Hông (vè sau) xe / thùng xe': 'Vè sau',
    'Cốp sau / Cửa hậu': 'Cốp sau',
    'Kính chắn gió trước': 'Kính chắn gió trước',
    'Kính chắn gió sau': 'Kính chắn gió sau',
  };

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) return const SizedBox.expand();
    return CustomPaint(
      painter: _CarPartLabelPainter(detections),
      size: Size.infinite,
    );
  }
}

class _CarPartLabelPainter extends CustomPainter {
  _CarPartLabelPainter(this.detections);

  final List<SegmentDetection> detections;

  @override
  void paint(Canvas canvas, Size size) {
    // Camera frames là landscape; canvas Flutter là portrait (app khoá dọc),
    // người dùng cầm máy ngang. Toàn bộ UI khác xoay 90° (RotatedBox
    // quarterTurns:1) nên nhãn cũng phải xoay 90° theo chiều kim đồng hồ để
    // đọc ngang đúng hướng. Tâm nhãn tính theo bounding box:
    //   screen_x = (1 - centerY) * W,  screen_y = centerX * H
    final w = size.width;
    final h = size.height;

    for (final d in detections) {
      final label = CarPartLabelOverlay._partDisplayNames[d.className];
      if (label == null) continue;

      final box = d.normalizedBox;
      // Tâm bộ phận (toạ độ portrait của màn hình).
      final dx = (1 - box.centerY) * w;
      final dy = box.centerX * h;

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w500,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      const padH = 12.0;
      const padV = 6.0;
      final rectWidth = tp.width + padH * 2;
      final rectHeight = tp.height + padV * 2;

      // Xoay quanh tâm bộ phận 90° theo chiều kim đồng hồ rồi vẽ nhãn căn giữa.
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(math.pi / 2);

      final left = -rectWidth / 2;
      final top = -rectHeight / 2;
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, rectWidth, rectHeight),
        const Radius.circular(18),
      );
      canvas.drawRRect(
        bgRect,
        Paint()..color = const Color(0xFF4A4A4A).withValues(alpha: 0.85),
      );
      tp.paint(canvas, Offset(left + padH, top + padV));

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CarPartLabelPainter old) => old.detections != detections;
}
