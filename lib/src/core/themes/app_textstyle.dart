import 'package:flutter/material.dart';

import '../utils/screen_utils.dart';
import 'app_colors.dart';
import 'app_fonts.dart';

/// Standardized textstyle
class AppTextStyles {
  AppTextStyles._();
  static TextStyle base = TextStyle(
    fontFamily: AppFonts.inter,
    fontSize: 16.sp,
    fontWeight: FontWeight.normal,
    color: AppColors.black,
  );
  static TextStyle baseWhite = TextStyle(
    fontFamily: AppFonts.inter,
    fontSize: 16.sp,
    fontWeight: FontWeight.normal,
    color: AppColors.white,
  );
  static TextStyle baseHyperLink = TextStyle(
    fontFamily: AppFonts.inter,
    fontSize: 16.sp,
    fontWeight: FontWeight.normal,
    color: AppColors.primaryA500,
  );
}

extension CFontWeight on TextStyle {
  /// FontWeight.w100
  TextStyle w100([double? fontSize]) => copyWith(
        fontWeight: FontWeight.w100,
        fontSize: fontSize,
      );

  /// FontWeight.w200
  TextStyle w200([double? fontSize]) => copyWith(
        fontWeight: FontWeight.w200,
        fontSize: fontSize,
      );

  /// FontWeight.w300
  TextStyle w300([double? fontSize]) => copyWith(
        fontWeight: FontWeight.w300,
        fontSize: fontSize,
      );

  /// FontWeight.w400
  TextStyle w400([double? fontSize]) => copyWith(
        fontWeight: FontWeight.w400,
        fontSize: fontSize,
      );

  /// FontWeight.w500
  TextStyle w500([double? fontSize]) => copyWith(
        fontWeight: FontWeight.w500,
        fontSize: fontSize,
      );

  /// FontWeight.w600
  TextStyle w600([double? fontSize]) => copyWith(
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
      );

  /// FontWeight.w700
  TextStyle w700([double? fontSize]) => copyWith(
        fontWeight: FontWeight.w700,
        fontSize: fontSize,
      );

  /// FontWeight.w800
  TextStyle w800([double? fontSize]) => copyWith(
        fontWeight: FontWeight.w800,
        fontSize: fontSize,
      );

  /// FontWeight.w900
  TextStyle w900([double? fontSize]) => copyWith(
        fontWeight: FontWeight.w900,
        fontSize: fontSize,
      );
}

extension CFontSize on TextStyle {
  /// custom fontSize
  TextStyle fSize(double fontSize) => copyWith(
        fontSize: fontSize,
      );

  /// fontSize: 10
  TextStyle get s10 => copyWith(
        fontSize: 10.sp,
      );

  /// fontSize: 12
  TextStyle get s12 => copyWith(
        fontSize: 12.sp,
      );

  /// fontSize: 14
  TextStyle get s14 => copyWith(
        fontSize: 14.sp,
      );

  /// fontSize: 16
  TextStyle get s16 => copyWith(
        fontSize: 16.sp,
      );

  /// fontSize: 18
  TextStyle get s18 => copyWith(
        fontSize: 18.sp,
      );

  /// fontSize: 20
  TextStyle get s20 => copyWith(
        fontSize: 20.sp,
      );

  /// fontSize: 24
  TextStyle get s24 => copyWith(
        fontSize: 24.sp,
      );

  /// fontSize: 32
  TextStyle get s32 => copyWith(
        fontSize: 32.sp,
      );

  /// fontSize: 36
  TextStyle get s36 => copyWith(
        fontSize: 36.sp,
      );

  /// fontSize: 40
  TextStyle get s40 => copyWith(
        fontSize: 40.sp,
      );

  /// fontSize: 48
  TextStyle get s48 => copyWith(
        fontSize: 48.sp,
      );
}

extension CFontColor on TextStyle {
  /// custom color
  TextStyle setColor(Color? color) => copyWith(color: color);

  /// color: AppColors.whiteColor,
  TextStyle get whiteColor => copyWith(color: AppColors.white);

  /// color: AppColors.blackColor,
  TextStyle get blackColor => copyWith(color: AppColors.black);

  /// color: AppColors.redA500Color,
  TextStyle get redA500Color => copyWith(color: AppColors.redA500);

  /// color: AppColors.redA400Color,
  TextStyle get redA400Color => copyWith(color: AppColors.redA400);

  /// color: AppColors.ink100;
  TextStyle get ink100Color => copyWith(color: AppColors.inkA100);

  /// color: AppColors.ink200;
  TextStyle get ink200Color => copyWith(color: AppColors.inkA200);

  /// color: AppColors.ink300;
  TextStyle get ink300Color => copyWith(color: AppColors.inkA300);

  /// color: AppColors.ink400;
  TextStyle get ink400Color => copyWith(color: AppColors.inkA400);

  /// color: AppColors.ink500;
  TextStyle get ink500Color => copyWith(color: AppColors.inkA500);

  /// color: AppColors.primaryColor;
  TextStyle get primaryColor => copyWith(color: AppColors.primaryA500);
}

extension CFontStyle on TextStyle {
  /// color: AppColors.white,
  TextStyle get italic => copyWith(fontStyle: FontStyle.italic);
}

extension CFontDecoration on TextStyle {
  /// decoration: TextDecoration.overline,
  TextStyle get overline => copyWith(decoration: TextDecoration.overline);

  /// decoration: TextDecoration.underline,
  TextStyle get underline => copyWith(decoration: TextDecoration.underline);

  /// decoration: TextDecoration.overline,
  TextStyle get noneDecoration => copyWith(decoration: TextDecoration.none);

  /// decoration: TextDecoration.lineThrough,
  TextStyle get lineThrough => copyWith(decoration: TextDecoration.lineThrough);
}
