import 'package:flutter/material.dart';

import '../../../../core/themes/app_colors.dart';
import '../../../../core/themes/app_textstyle.dart';
import '../../../../core/utils/screen_utils.dart';

/// Trạng thái của một bước trong [StepLine].
enum StepState {
  /// Đã hoàn thành — vòng tròn nền nhạt + dấu tick.
  completed,

  /// Đang thực hiện — vòng tròn nền đậm + icon.
  active,

  /// Chưa tới — vòng tròn xám nhạt.
  inactive,
}

/// Mô tả một bước hiển thị trên [StepLine].
class StepData {
  const StepData({required this.label, this.activeIcon = Icons.edit});

  /// Nhãn hiển thị bên dưới vòng tròn.
  final String label;

  /// Icon hiển thị khi bước ở trạng thái [StepState.active].
  final IconData activeIcon;
}

/// Stepper ngang hiển thị tiến trình các bước chụp ảnh.
///
/// Bước có index < [currentIndex] là [StepState.completed] (dấu tick),
/// bước = [currentIndex] là [StepState.active] (icon), còn lại
/// là [StepState.inactive].
class StepLine extends StatelessWidget {
  const StepLine({
    super.key,
    required this.steps,
    required this.currentIndex,
  });

  final List<StepData> steps;
  final int currentIndex;

  StepState _stateFor(int index) {
    if (index < currentIndex) return StepState.completed;
    if (index == currentIndex) return StepState.active;
    return StepState.inactive;
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (int i = 0; i < steps.length; i++) {
      children.add(_StepNode(data: steps[i], state: _stateFor(i)));
      if (i != steps.length - 1) {
        // Đường nối tô đậm khi bước bên trái đã hoàn thành.
        final filled = i < currentIndex;
        children.add(
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: 22.h),
              child: Container(
                height: 2.h,
                color: filled ? AppColors.primaryA500 : AppColors.inkA200,
              ),
            ),
          ),
        );
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _StepNode extends StatelessWidget {
  const _StepNode({required this.data, required this.state});

  final StepData data;
  final StepState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildCircle(),
        6.verticalSpace,
        SizedBox(
          width: 72.w,
          child: Text(
            data.label,
            textAlign: TextAlign.center,
            style: state == StepState.active
                ? AppTextStyles.base.s12.w600().setColor(AppColors.primaryA500)
                : AppTextStyles.base.s12.w400().setColor(AppColors.inkA400),
          ),
        ),
      ],
    );
  }

  Widget _buildCircle() {
    switch (state) {
      case StepState.completed:
        return Container(
          width: 32.r,
          height: 32.r,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryA200,
          ),
          child: Icon(
            Icons.check_rounded,
            size: 18.r,
            color: AppColors.primaryA500,
          ),
        );
      case StepState.active:
        return Container(
          width: 32.r,
          height: 32.r,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryA500,
          ),
          child: Icon(
            data.activeIcon,
            size: 16.r,
            color: AppColors.white,
          ),
        );
      case StepState.inactive:
        return Container(
          width: 32.r,
          height: 32.r,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.inkA100,
            border: Border.all(color: AppColors.inkA200, width: 1.5),
          ),
        );
    }
  }
}
