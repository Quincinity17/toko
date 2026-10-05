import 'dart:io';

/// Jenis perangkat yang sedang menjalankan aplikasi (bukan ukuran layar —
/// itu [AppBreakpoints]). Memakai `dart:io` karena `defaultTargetPlatform`
/// selalu Android di lingkungan tes.
abstract final class Device {
  /// Untuk tes: paksa dianggap HP/tablet Android (`true`) atau komputer.
  static bool? debugAndroidOverride;

  static bool get isAndroid => debugAndroidOverride ?? Platform.isAndroid;

  /// HP/tablet layar sentuh: tanpa keyboard fisik, tanpa tombol pintas,
  /// tanpa spooler printer / folder yang bisa dibuka.
  static bool get isTouch =>
      debugAndroidOverride ?? (Platform.isAndroid || Platform.isIOS);

  /// "Bayar  (F2)" di komputer, "Bayar" di HP/tablet.
  static String withShortcut(String label, String key) =>
      isTouch ? label : '$label  ($key)';
}
