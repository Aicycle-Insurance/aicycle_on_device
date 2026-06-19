import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/string_sheet.dart';
import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';

/// Nút "Xem kết quả" hai bước chống chạm nhầm:
/// - Mặc định opacity 20% (disabled).
/// - Chạm lần đầu → opacity 100% + enable trong 5s.
/// - Chạm khi đang enable → gọi [onPressed].
/// - 5s không chạm → tự trở về disabled (opacity 20%).
class ViewResultButton extends StatefulWidget {
  const ViewResultButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<ViewResultButton> createState() => _ViewResultButtonState();
}

class _ViewResultButtonState extends State<ViewResultButton> {
  bool _enabled = false;
  Timer? _timer;

  void _onTap() {
    if (_enabled) {
      _timer?.cancel();
      widget.onPressed();
      return;
    }
    setState(() => _enabled = true);
    _resetTimer();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _enabled = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedOpacity(
        opacity: _enabled ? 1.0 : 0.2,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: AppColors.primaryA500,
            borderRadius: BorderRadius.circular(28.r),
          ),
          child: Text(
            StringSheet.viewResult,
            style: AppTextStyles.baseWhite.s14.w600(),
          ),
        ),
      ),
    );
  }
}
