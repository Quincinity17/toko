import 'package:flutter/widgets.dart';

/// Jarak standar (kelipatan 4, seperti grid iOS).
class AppSpacing {
  const AppSpacing._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Padding kiri-kanan konten halaman.
  static const double pageGutter = 32;
}

class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
}

class AppSizes {
  const AppSizes._();

  /// Tinggi minimum target sentuh; lebih besar dari 44pt iOS agar nyaman
  /// dipakai kasir di layar sentuh.
  static const double touchTarget = 48;
  static const double buttonLarge = 56;

  static const double sidebarExpanded = 248;
  static const double sidebarCollapsed = 76;

  static const double contentMaxWidth = 1200;
}

class AppDurations {
  const AppDurations._();

  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 350);
  static const slow = Duration(milliseconds: 500);
}
