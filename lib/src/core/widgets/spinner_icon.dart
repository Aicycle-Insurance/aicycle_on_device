import 'package:flutter/material.dart';

import '../constants/app_assets.dart';

class SpinnerIcon extends StatelessWidget {
  const SpinnerIcon({super.key, this.size = 16});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        AppAssets.spinner,
        fit: BoxFit.contain,
        package: 'aicycle_on_device',
      ),
    );
  }
}
