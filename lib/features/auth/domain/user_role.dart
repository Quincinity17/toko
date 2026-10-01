import '../../../core/router/routes.dart';

/// Peran user. Disimpan di database sebagai nama enum (`admin` / `kasir`),
/// jadi urutan nilai boleh berubah tanpa merusak data.
enum UserRole {
  admin('Admin'),
  kasir('Kasir');

  const UserRole(this.label);

  final String label;

  /// Halaman pertama setelah login.
  String get homePath => switch (this) {
    UserRole.admin => AppRoutes.dashboard,
    UserRole.kasir => AppRoutes.kasir,
  };

  /// Halaman yang boleh dibuka. Admin bebas; kasir hanya Kasir dan Dashboard.
  bool canAccess(String path) => switch (this) {
    UserRole.admin => true,
    UserRole.kasir =>
      path.startsWith(AppRoutes.kasir) || path.startsWith(AppRoutes.dashboard),
  };
}
