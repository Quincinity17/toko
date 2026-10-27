import '../../../core/router/routes.dart';

/// Peran user. Disimpan di database sebagai nama enum (`admin` /
/// `supervisor` / `kasir`), jadi urutan nilai boleh berubah tanpa merusak data.
///
/// Admin tidak terikat toko dan punya semua hak akses. Supervisor dan kasir
/// terikat ke satu toko; hak aksesnya diatur admin (lihat `Permission`,
/// `AppUser.can`/`canAccess`).
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
}
