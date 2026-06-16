import 'package:aicycle_on_device/src/core/utils/screen_utils.dart';
import 'package:flutter/material.dart';

import '../../../../core/themes/app_colors.dart';
import '../../../../core/widgets/arrows_icon.dart';
import '../../../../core/widgets/spinner_icon.dart';

enum MessageType { guide, loading, info, error, success, warning }

class CameraMessage {
  final String message;
  final MessageType type;

  CameraMessage({
    required this.message,
    this.type = MessageType.info,
  });

  Widget get icon {
    switch (type) {
      case MessageType.guide:
        return ArrowsIcon();
      case MessageType.loading:
        return SpinnerIcon();
      case MessageType.info:
        return Container(
          width: 24.r,
          height: 24.r,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryA500,
          ),
          child: Center(
            child: Text(
              'i',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.r,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      case MessageType.error:
        return const Icon(Icons.error_outline, color: Colors.redAccent);
      case MessageType.warning:
        return Icon(Icons.warning_rounded,
            color: AppColors.orangeA500, size: 24.r);
      case MessageType.success:
        return Container(
          width: 24.r,
          height: 24.r,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.neonTech,
          ),
          child: Center(
            child: Icon(Icons.check_rounded, color: Colors.white, size: 16.r),
          ),
        );
    }
  }
}
