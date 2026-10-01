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
    this.lastLoginAt,
  });

  final int id;
  final String username;
  final String fullName;
  final UserRole role;
  final DateTime? lastLoginAt;

  bool get isAdmin => role == UserRole.admin;

  /// Maksimal dua huruf, untuk avatar: "Kasir Pagi" → "KP".
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final letters = parts.where((p) => p.isNotEmpty).take(2).map((p) => p[0]);
    final result = letters.join().toUpperCase();
    return result.isEmpty ? '?' : result;
  }

  @override
  bool operator ==(Object other) => other is AppUser && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
