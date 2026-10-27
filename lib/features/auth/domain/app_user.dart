import 'package:flutter/foundation.dart';

import '../../../core/router/routes.dart';
import 'permission.dart';
import 'user_role.dart';

/// User yang sedang/bisa login. Tidak membawa password hash supaya hash tidak
/// pernah keluar dari lapisan data.
@immutable
class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.isActive = true,
    this.lastLoginAt,
    this.storeId,
    this.permissions = const {},
  });

  final int id;
  final String username;
  final String fullName;
  final UserRole role;
  final bool isActive;
  final DateTime? lastLoginAt;

  /// Toko supervisor/kasir; `null` untuk admin (semua toko).
  final int? storeId;

  /// Hak akses peran ini (dimuat saat login dari Pengaturan › Hak Akses
  /// Peran). Admin selalu punya semua, apa pun isinya.
  final Set<Permission> permissions;

  bool get isAdmin => role == UserRole.admin;

  bool can(Permission p) => isAdmin || permissions.contains(p);

  /// Boleh mengubah stok toko [storeId] (admin semua toko; peran lain hanya
  /// tokonya, bila punya hak "Ubah stok").
  bool canAdjustStockAt(int storeId) =>
      isAdmin || (can(Permission.adjustStock) && this.storeId == storeId);

  /// Halaman yang boleh dibuka. Admin bebas. Peran lain: Kasir dan
  /// Pengaturan versi ringkas (bukan sub-halamannya) selalu; Dashboard, Stok,
  /// dan Laporan sesuai hak aksesnya.
  bool canAccess(String path) {
    if (isAdmin) return true;
    if (path.startsWith(AppRoutes.kasir) || path == AppRoutes.pengaturan) {
      return true;
    }
    if (path.startsWith(AppRoutes.dashboard)) {
      return can(Permission.viewDashboard);
    }
    if (path.startsWith(AppRoutes.stok)) return can(Permission.viewStock);
    if (path.startsWith(AppRoutes.laporan)) return can(Permission.viewReports);
    return false;
  }

  /// Boleh berjualan di toko [storeId] (admin semua toko).
  bool canSellAt(int storeId) => isAdmin || this.storeId == storeId;

  /// Maksimal dua huruf, untuk avatar: "Kasir Pagi" → "KP".
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final letters = parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0]);
    final result = letters.join().toUpperCase();
    return result.isEmpty ? '?' : result;
  }

  AppUser copyWith({
    String? fullName,
    UserRole? role,
    bool? isActive,
    DateTime? lastLoginAt,
    int? storeId,
    Set<Permission>? permissions,
  }) {
    return AppUser(
      id: id,
      username: username,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      storeId: storeId ?? this.storeId,
      permissions: permissions ?? this.permissions,
    );
  }

  // Dibandingkan per nilai supaya perubahan nama/peran ikut memicu rebuild.
  @override
  bool operator ==(Object other) =>
      other is AppUser &&
      other.id == id &&
      other.username == username &&
      other.fullName == fullName &&
      other.role == role &&
      other.isActive == isActive &&
      other.lastLoginAt == lastLoginAt &&
      other.storeId == storeId &&
      setEquals(other.permissions, permissions);

  @override
  int get hashCode => Object.hash(
    id,
    username,
    fullName,
    role,
    isActive,
    lastLoginAt,
    storeId,
    Object.hashAllUnordered(permissions),
  );
}
