import 'package:flutter/material.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/utils/screen_utils.dart';

class CarCorner extends StatelessWidget {
  const CarCorner({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 67.r,
      height: 67.r,
      child: Center(
        child: Image.asset(
          AppAssets.car,
          fit: BoxFit.cover,
          package: 'aicycle_on_device',
        ),
      ),
    );
  }
}
