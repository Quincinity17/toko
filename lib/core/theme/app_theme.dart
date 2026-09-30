import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_metrics.dart';
import 'app_typography.dart';

export 'app_colors.dart';
export 'app_metrics.dart';
export 'app_typography.dart';
export 'spring_curve.dart';

/// Tema aplikasi. Memakai MaterialApp sebagai kerangka (lokalisasi, scrollbar
/// desktop, seleksi teks), tetapi komponen yang tampil bergaya Cupertino.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light, AppColors.light);
  static ThemeData get dark => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors c) {
    final textTheme = AppTypography.textTheme(c);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: c.accent,
            brightness: brightness,
          ).copyWith(
            primary: c.accent,
            error: c.danger,
            surface: c.card,
            onSurface: c.label,
          ),
      textTheme: textTheme,
      dividerColor: c.separator,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: c.hover,
      focusColor: c.accentTint,
      visualDensity: VisualDensity.standard,
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
        thumbColor: WidgetStateProperty.all(c.labelTertiary),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.cardElevated,
          borderRadius: AppRadius.smAll,
          boxShadow: [
            BoxShadow(
              color: c.shadow,
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        textStyle: AppTypography.footnote.copyWith(color: c.label),
        waitDuration: const Duration(milliseconds: 600),
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: c.accent,
        scaffoldBackgroundColor: c.background,
        barBackgroundColor: c.card.withValues(alpha: 0.7),
        textTheme: CupertinoTextThemeData(
          primaryColor: c.accent,
          textStyle: AppTypography.body.copyWith(color: c.label),
          navLargeTitleTextStyle: AppTypography.largeTitle.copyWith(
            color: c.label,
          ),
          navTitleTextStyle: AppTypography.headline.copyWith(color: c.label),
          actionTextStyle: AppTypography.body.copyWith(color: c.accent),
        ),
      ),
      extensions: [c],
    );
  }
}
