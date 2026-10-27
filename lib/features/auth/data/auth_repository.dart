import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/seals_dao.dart';
import '../../../core/database/tables/audit.dart';
import '../../../core/security/password_hasher.dart';
import '../domain/app_user.dart';
import '../domain/user_role.dart';

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

  /// Memeriksa username dan password. Pesan gagal sengaja sama untuk username
  /// tidak ada dan password salah.
  Future<AppUser> login(String username, String password) async {
    if (username.trim().isEmpty || password.isEmpty) {
      throw const AuthFailure('Isi username dan password.');
    }

    final row = await _db.usersDao.findByUsername(username);
    if (row == null || !await _hasher.verify(password, row.passwordHash)) {
      await _db.auditDao.append(
        type: AuditType.loginFailed,
        summary: 'Login gagal: "${username.trim()}"',
        userId: row?.id,
        userName: row?.fullName,
        storeId: row?.storeId,
        data: {'username': username.trim()},
        at: _clock(),
      );
      throw const AuthFailure('Username atau password salah.');
    }
    // Segel akun: role/toko/password yang diubah di luar aplikasi (mis.
    // kasir menjadikan dirinya admin lewat DB Browser) → ditolak.
    if (!_db.sealer.verify(row.seal, SealsDao.userFields(row))) {
      await _db.auditDao.append(
        type: AuditType.loginFailed,
        summary:
            'Login ditolak: data akun "${row.username}" diubah di luar '
            'aplikasi',
        userId: row.id,
        userName: row.fullName,
        storeId: row.storeId,
        data: {'username': row.username, 'reason': 'seal'},
        at: _clock(),
      );
      throw const AuthFailure(
        'Data akun ini tidak sah (diubah di luar aplikasi). Hubungi admin.',
      );
    }
    if (!row.isActive) {
      throw const AuthFailure('Akun ini dinonaktifkan. Hubungi admin.');
    }
    if (row.role.needsStore) {
      final store = row.storeId == null
          ? null
          : await _db.storesDao.findById(row.storeId!);
      if (store == null || !store.isActive) {
        throw const AuthFailure(
          'Toko untuk akun ini belum diatur atau sudah nonaktif. '
          'Hubungi admin.',
        );
      }
    }

    final now = _clock();
    await _db.usersDao.touchLastLogin(row.id, now);
    await _db.auditDao.append(
      type: AuditType.login,
      summary: 'Login ${row.fullName} (${row.role.label})',
      userId: row.id,
      userName: row.fullName,
      storeId: row.storeId,
      at: now,
    );
    return userFromRow(row).copyWith(
      lastLoginAt: now,
      permissions: row.role == UserRole.admin
          ? null
          : await _db.rolePermissionsDao.permissionsOf(row.role),
    );
  }
}

/// Mengubah baris tabel menjadi model domain (tanpa password hash).
AppUser userFromRow(UserRow row) => AppUser(
  id: row.id,
  username: row.username,
  fullName: row.fullName,
  role: row.role,
  isActive: row.isActive,
  lastLoginAt: row.lastLoginAt,
  storeId: row.storeId,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(passwordHasherProvider),
  ),
);
