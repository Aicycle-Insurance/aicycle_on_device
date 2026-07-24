import 'package:flutter/material.dart';

import 'app_fonts.dart';

/// Global theme configuration for SDK screens.
class AppTheme {
  AppTheme._();

  static const String fontFamily = AppFonts.inter;

  static ThemeData apply(ThemeData base) {
    final textTheme = base.textTheme.apply(
      fontFamily: fontFamily,
      bodyColor: base.textTheme.bodyMedium?.color,
      displayColor: base.textTheme.displayMedium?.color,
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: fontFamily),
    );
  }
}
