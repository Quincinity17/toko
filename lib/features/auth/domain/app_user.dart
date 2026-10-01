import 'package:flutter/foundation.dart';

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
  });

  final int id;
  final String username;
  final String fullName;
  final UserRole role;
  final bool isActive;
  final DateTime? lastLoginAt;

  bool get isAdmin => role == UserRole.admin;

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
  }) {
    return AppUser(
      id: id,
      username: username,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
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
      other.lastLoginAt == lastLoginAt;

  @override
  int get hashCode =>
      Object.hash(id, username, fullName, role, isActive, lastLoginAt);
}
