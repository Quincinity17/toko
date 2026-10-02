import 'package:flutter/material.dart';

/// Palet warna bergaya Apple (iOS system colors).
///
/// Diakses lewat `context.colors` (lihat [AppColorsX]) supaya otomatis
/// mengikuti mode terang/gelap.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.card,
    required this.cardElevated,
    required this.sidebar,
    required this.separator,
    required this.fill,
    required this.fillSecondary,
    required this.label,
    required this.labelSecondary,
    required this.labelTertiary,
    required this.accent,
    required this.accentTint,
    required this.success,
    required this.danger,
    required this.warning,
    required this.hover,
    required this.shadow,
    required this.chart2,
    required this.purple,
  });

  /// Latar belakang utama (systemGroupedBackground).
  final Color background;

  /// Permukaan kartu / grup list (secondarySystemGroupedBackground).
  final Color card;

  /// Kartu di atas kartu, misalnya sheet atau popover.
  final Color cardElevated;

  /// Warna dasar sidebar sebelum efek kaca.
  final Color sidebar;
  final Color separator;

  /// Isi field input, chip, dan segmented control.
  final Color fill;
  final Color fillSecondary;
  final Color label;
  final Color labelSecondary;
  final Color labelTertiary;
  final Color accent;

  /// Aksen transparan untuk latar item terpilih / tombol "tinted".
  final Color accentTint;
  final Color success;
  final Color danger;
  final Color warning;
  final Color hover;
  final Color shadow;

  /// Seri kedua grafik (seri pertama = [accent]). Divalidasi bersama aksen
  /// untuk buta warna dan kontras di mode terang (#007AFF) dan gelap (#0A84FF).
  /// Bukan warna status, jadi tidak dipakai untuk peringatan.
  final Color chart2;

  /// Ungu sistem Apple. Warna peran supervisor (admin biru, kasir hijau).
  final Color purple;

  static const light = AppColors(
    background: Color(0xFFF2F2F7),
    card: Color(0xFFFFFFFF),
    cardElevated: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF7F7FA),
    separator: Color(0x4A3C3C43),
    fill: Color(0x1F767680),
    fillSecondary: Color(0x14767680),
    label: Color(0xFF000000),
    labelSecondary: Color(0x993C3C43),
    labelTertiary: Color(0x4D3C3C43),
    accent: Color(0xFF007AFF),
    accentTint: Color(0x1F007AFF),
    success: Color(0xFF34C759),
    danger: Color(0xFFFF3B30),
    warning: Color(0xFFFF9500),
    hover: Color(0x0A000000),
    shadow: Color(0x0F000000),
    chart2: Color(0xFFD55181),
    purple: Color(0xFFAF52DE),
  );

  static const dark = AppColors(
    background: Color(0xFF000000),
    card: Color(0xFF1C1C1E),
    cardElevated: Color(0xFF2C2C2E),
    sidebar: Color(0xFF1C1C1E),
    separator: Color(0x99545458),
    fill: Color(0x3D767680),
    fillSecondary: Color(0x29767680),
    label: Color(0xFFFFFFFF),
    labelSecondary: Color(0x99EBEBF5),
    labelTertiary: Color(0x4DEBEBF5),
    accent: Color(0xFF0A84FF),
    accentTint: Color(0x330A84FF),
    success: Color(0xFF30D158),
    danger: Color(0xFFFF453A),
    warning: Color(0xFFFF9F0A),
    hover: Color(0x14FFFFFF),
    shadow: Color(0x00000000),
    chart2: Color(0xFFD55181),
    purple: Color(0xFFBF5AF2),
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? card,
    Color? cardElevated,
    Color? sidebar,
    Color? separator,
    Color? fill,
    Color? fillSecondary,
    Color? label,
    Color? labelSecondary,
    Color? labelTertiary,
    Color? accent,
    Color? accentTint,
    Color? success,
    Color? danger,
    Color? warning,
    Color? hover,
    Color? shadow,
    Color? chart2,
    Color? purple,
  }) {
    return AppColors(
      background: background ?? this.background,
      card: card ?? this.card,
      cardElevated: cardElevated ?? this.cardElevated,
      sidebar: sidebar ?? this.sidebar,
      separator: separator ?? this.separator,
      fill: fill ?? this.fill,
      fillSecondary: fillSecondary ?? this.fillSecondary,
      label: label ?? this.label,
      labelSecondary: labelSecondary ?? this.labelSecondary,
      labelTertiary: labelTertiary ?? this.labelTertiary,
      accent: accent ?? this.accent,
      accentTint: accentTint ?? this.accentTint,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      hover: hover ?? this.hover,
      shadow: shadow ?? this.shadow,
      chart2: chart2 ?? this.chart2,
      purple: purple ?? this.purple,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      card: l(card, other.card),
      cardElevated: l(cardElevated, other.cardElevated),
      sidebar: l(sidebar, other.sidebar),
      separator: l(separator, other.separator),
      fill: l(fill, other.fill),
      fillSecondary: l(fillSecondary, other.fillSecondary),
      label: l(label, other.label),
      labelSecondary: l(labelSecondary, other.labelSecondary),
      labelTertiary: l(labelTertiary, other.labelTertiary),
      accent: l(accent, other.accent),
      accentTint: l(accentTint, other.accentTint),
      success: l(success, other.success),
      danger: l(danger, other.danger),
      warning: l(warning, other.warning),
      hover: l(hover, other.hover),
      shadow: l(shadow, other.shadow),
      chart2: l(chart2, other.chart2),
      purple: l(purple, other.purple),
    );
  }
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
