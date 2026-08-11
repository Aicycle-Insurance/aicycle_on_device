import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/screen_utils.dart';

class ManualCaptureHintHand extends StatefulWidget {
  const ManualCaptureHintHand({
    super.key,
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  State<ManualCaptureHintHand> createState() => _ManualCaptureHintHandState();
}

class _ManualCaptureHintHandState extends State<ManualCaptureHintHand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _move;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _move = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _move,
        builder: (context, child) => Transform.translate(
          offset: Offset(-20.r, _move.value * 50.h),
          child: child,
        ),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Transform.rotate(
            angle: math.pi / 2,
            child: Image.asset(
              AppAssets.hand,
              fit: BoxFit.contain,
              package: 'aicycle_on_device',
            ),
          ),
        ),
      ),
    );
  }
}
