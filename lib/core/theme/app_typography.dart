import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Hierarki teks mengikuti iOS Dynamic Type (ukuran default "Large"),
/// memakai Inter sebagai pengganti SF Pro.
class AppTypography {
  const AppTypography._();

  static const fontFamily = 'Inter';

  static const largeTitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    height: 1.2,
  );
  static const title1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    height: 1.2,
  );
  static const title2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    height: 1.25,
  );
  static const title3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.25,
  );
  static const headline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.3,
  );
  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.3,
    height: 1.3,
  );
  static const callout = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    height: 1.3,
  );
  static const subheadline = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
    height: 1.3,
  );
  static const footnote = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    height: 1.3,
  );
  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.3,
  );

  /// Angka besar untuk total belanja di layar kasir.
  static const displayAmount = TextStyle(
    fontFamily: fontFamily,
    fontSize: 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -1,
    height: 1.1,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static TextTheme textTheme(AppColors c) {
    return TextTheme(
      displayLarge: largeTitle.copyWith(color: c.label),
      headlineLarge: title1.copyWith(color: c.label),
      headlineMedium: title2.copyWith(color: c.label),
      headlineSmall: title3.copyWith(color: c.label),
      titleLarge: title3.copyWith(color: c.label),
      titleMedium: headline.copyWith(color: c.label),
      titleSmall: subheadline.copyWith(
        color: c.label,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: body.copyWith(color: c.label),
      bodyMedium: callout.copyWith(color: c.label),
      bodySmall: footnote.copyWith(color: c.labelSecondary),
      labelLarge: headline.copyWith(color: c.label),
      labelMedium: footnote.copyWith(color: c.labelSecondary),
      labelSmall: caption.copyWith(color: c.labelSecondary),
    );
  }
}
