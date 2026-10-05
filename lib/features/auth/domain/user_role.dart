import '../../../core/router/routes.dart';

/// Peran user. Disimpan di database sebagai nama enum (`admin` /
/// `supervisor` / `kasir`), jadi urutan nilai boleh berubah tanpa merusak data.
///
/// Admin tidak terikat toko. Supervisor dan kasir terikat ke satu toko;
/// bedanya hanya supervisor boleh mengubah stok tokonya (halaman Stok).
enum UserRole {
  admin('Admin'),
  supervisor('Supervisor'),
  kasir('Kasir');

  const UserRole(this.label);

  final String label;

  /// Halaman pertama setelah login.
  String get homePath => switch (this) {
    UserRole.admin => AppRoutes.dashboard,
    UserRole.supervisor || UserRole.kasir => AppRoutes.kasir,
  };

  /// Terikat ke satu toko (supervisor & kasir).
  bool get needsStore => this != UserRole.admin;

  /// Boleh mengubah stok barang (admin semua toko, supervisor tokonya).
  bool get canAdjustStock => this != UserRole.kasir;

  /// Halaman yang boleh dibuka. Admin bebas; kasir hanya halaman Kasir
  /// (transaksi baru dan daftar pembayaran hari ini); supervisor Kasir + Stok.
  /// Supervisor & kasir juga membuka Pengaturan (versi ringkas: terminal,
  /// backup, tampilan, tentang), tetapi tidak sub-halamannya.
  bool canAccess(String path) => switch (this) {
    UserRole.admin => true,
    UserRole.supervisor =>
      path.startsWith(AppRoutes.kasir) ||
          path.startsWith(AppRoutes.stok) ||
          path == AppRoutes.pengaturan,
    UserRole.kasir =>
      path.startsWith(AppRoutes.kasir) || path == AppRoutes.pengaturan,
  };
}
