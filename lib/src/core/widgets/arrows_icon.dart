import 'package:flutter/material.dart';

import '../constants/app_assets.dart';

class ArrowsIcon extends StatelessWidget {
  const ArrowsIcon({
    super.key,
    this.width = 40,
    this.height = 12,
  });
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Image.asset(
        AppAssets.arrows,
        fit: BoxFit.fitWidth,
        package: 'aicycle_on_device',
      ),
    );
  }
}
