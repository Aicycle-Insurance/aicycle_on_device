import 'dart:math';
import 'package:flutter/material.dart';

class ScreenUtil {
  static const Size defaultSize = Size(375, 812);
  static final ScreenUtil _instance = ScreenUtil._();

  late Size _designSize;
  late double _screenWidth;
  late double _screenHeight;
  late bool _minTextAdapt;

  ScreenUtil._();

  factory ScreenUtil() {
    return _instance;
  }

  static void init(
    BuildContext context, {
    Size designSize = defaultSize,
    bool minTextAdapt = false,
    bool forcePortrait = false,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    _instance._designSize = designSize;
    _instance._screenWidth =
        forcePortrait ? min(size.width, size.height) : size.width;
    _instance._screenHeight =
        forcePortrait ? max(size.width, size.height) : size.height;
    _instance._minTextAdapt = minTextAdapt;
  }

  static ScreenUtil get instance => _instance;

  double get screenWidth => _screenWidth;
  double get screenHeight => _screenHeight;
  double get scaleWidth => _screenWidth / _designSize.width;
  double get scaleHeight => _screenHeight / _designSize.height;
  double get scaleText =>
      _minTextAdapt ? min(scaleWidth, scaleHeight) : scaleWidth;

  double setWidth(num width) => width * scaleWidth;
  double setHeight(num height) => height * scaleHeight;
  double setSp(num fontSize) => fontSize * scaleText;
  double setRadius(num radius) => radius * min(scaleWidth, scaleHeight);
}

extension ScreenUtilExtension on num {
  /// Scaled width
  double get w => ScreenUtil.instance.setWidth(this);

  /// Scaled height
  double get h => ScreenUtil.instance.setHeight(this);

  /// Scaled font size
  double get sp => ScreenUtil.instance.setSp(this);

  /// Scaled radius
  double get r => ScreenUtil.instance.setRadius(this);

  /// Horizontal spacing
  Widget get horizontalSpace => SizedBox(width: w);

  /// Vertical spacing
  Widget get verticalSpace => SizedBox(height: h);
}
