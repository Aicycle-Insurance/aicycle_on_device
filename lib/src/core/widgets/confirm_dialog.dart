import 'package:flutter/material.dart';

import '../constants/string_sheet.dart';
import '../themes/app_colors.dart';
import '../themes/app_textstyle.dart';

/// Hộp thoại xác nhận dùng chung cho SDK (ví dụ: thoát camera, kết thúc chụp ảnh...).
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    this.title,
    required this.content,
    this.cancelText,
    this.confirmText,
    this.confirmColor,
    this.quarterTurns = 0,
  });

  final String? title;
  final String content;
  final String? cancelText;
  final String? confirmText;
  final Color? confirmColor;
  final int quarterTurns;

  /// Hiển thị hộp thoại xác nhận và trả về `true` nếu người dùng chọn xác nhận.
  static Future<bool> show(
    BuildContext context, {
    String? title,
    required String content,
    String? cancelText,
    String? confirmText,
    Color? confirmColor,
    int quarterTurns = 0,
    bool barrierDismissible = true,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => ConfirmDialog(
        title: title,
        content: content,
        cancelText: cancelText,
        confirmText: confirmText,
        confirmColor: confirmColor,
        quarterTurns: quarterTurns,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final dialog = AlertDialog(
      title: title != null
          ? Text(
              title!,
              style: AppTextStyles.base.s16.w600(),
            )
          : null,
      content: Text(
        content,
        style: AppTextStyles.base.s14.ink400Color,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            cancelText ?? StringSheet.cancel,
            style: AppTextStyles.base.s14.w600(),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmText ?? StringSheet.confirm,
            style: AppTextStyles.base.s14.w600().copyWith(
                  color: confirmColor ?? AppColors.primaryA500,
                ),
          ),
        ),
      ],
    );

    if (quarterTurns != 0) {
      return RotatedBox(
        quarterTurns: quarterTurns,
        child: dialog,
      );
    }
    return dialog;
  }
}
