import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/security/password_hasher.dart';
import '../domain/app_user.dart';

/// Gagal login. [message] sudah siap ditampilkan ke user.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

class AuthRepository {
  AuthRepository(this._db, this._hasher, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final PasswordHasher _hasher;
  final DateTime Function() _clock;

  /// Akun yang ditampilkan di layar login.
  Future<List<AppUser>> activeUsers() async {
    final rows = await _db.usersDao.activeUsers();
    return rows.map(_toDomain).toList();
  }

  /// Memeriksa username dan password. Pesan gagal sengaja sama untuk username
  /// tidak ada dan password salah.
  Future<AppUser> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      throw const AuthFailure('Pilih akun dan isi password.');
    }

    final row = await _db.usersDao.findByUsername(username);
    if (row == null || !await _hasher.verify(password, row.passwordHash)) {
      throw const AuthFailure('Password salah. Coba lagi.');
    }
    if (!row.isActive) {
      throw const AuthFailure('Akun ini dinonaktifkan. Hubungi admin.');
    }

    final now = _clock();
    await _db.usersDao.touchLastLogin(row.id, now);
    return _toDomain(row).copyWithLastLogin(now);
  }

  AppUser _toDomain(UserRow row) => AppUser(
    id: row.id,
    username: row.username,
    fullName: row.fullName,
    role: row.role,
    lastLoginAt: row.lastLoginAt,
  );
}

extension on AppUser {
  AppUser copyWithLastLogin(DateTime at) => AppUser(
    id: id,
    username: username,
    fullName: fullName,
    role: role,
    lastLoginAt: at,
  );
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(passwordHasherProvider),
  ),
);
