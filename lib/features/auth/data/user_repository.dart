import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/security/password_hasher.dart';
import '../domain/account_rules.dart';
import '../domain/app_user.dart';
import '../domain/user_role.dart';
import 'auth_repository.dart';

/// Gagal mengelola akun. [message] siap ditampilkan ke user.
class AccountFailure implements Exception {
  const AccountFailure(this.message);

  final String message;

  @override
  String toString() => 'AccountFailure: $message';
}

/// Kelola akun: tambah, ubah, nonaktifkan, hapus, dan ganti password.
///
/// Aturan pengaman:
/// - Hanya admin yang boleh mengelola akun orang lain.
/// - Admin tidak bisa menonaktifkan, menurunkan peran, atau menghapus akunnya
///   sendiri (mencegah terkunci dari aplikasi).
/// - Harus selalu ada minimal satu admin aktif.
class UserRepository {
  UserRepository(this._db, this._hasher);

  final AppDatabase _db;
  final PasswordHasher _hasher;

  Stream<List<AppUser>> watchAll() {
    return _db.usersDao.watchAllUsers().map(
      (rows) => rows.map(userFromRow).toList(),
    );
  }

  Future<AppUser> create({
    required AppUser actor,
    required String username,
    required String fullName,
    required UserRole role,
    required String password,
  }) async {
    _requireAdmin(actor);
    _check(AccountRules.username(username));
    _check(AccountRules.fullName(fullName));
    _check(AccountRules.password(password));

    final normalized = AccountRules.normalizeUsername(username);
    if (await _db.usersDao.findByUsername(normalized) != null) {
      throw AccountFailure('Username "$normalized" sudah dipakai.');
    }

    final hash = await _hasher.hash(password);
    final id = await _db.usersDao.insertUser(
      UsersCompanion.insert(
        username: normalized,
        fullName: fullName.trim(),
        passwordHash: hash,
        role: role,
      ),
    );
    return userFromRow((await _db.usersDao.findById(id))!);
  }

  /// Mengubah nama, peran, dan status aktif. Username tidak bisa diubah.
  Future<AppUser> update({
    required AppUser actor,
    required int id,
    required String fullName,
    required UserRole role,
    required bool isActive,
  }) async {
    _requireAdmin(actor);
    _check(AccountRules.fullName(fullName));

    return _db.transaction(() async {
      final current = await _find(id);
      final staysActiveAdmin = isActive && role == UserRole.admin;

      if (id == actor.id && !staysActiveAdmin) {
        throw const AccountFailure(
          'Anda tidak bisa menonaktifkan atau mengubah peran akun sendiri.',
        );
      }
      if (_isActiveAdmin(current) && !staysActiveAdmin) {
        await _ensureAnotherActiveAdmin();
      }

      await _db.usersDao.updateUser(
        id,
        UsersCompanion(
          fullName: Value(fullName.trim()),
          role: Value(role),
          isActive: Value(isActive),
        ),
      );
      return userFromRow((await _db.usersDao.findById(id))!);
    });
  }

  /// Admin mengganti password akun lain tanpa perlu password lama.
  Future<void> resetPassword({
    required AppUser actor,
    required int id,
    required String newPassword,
  }) async {
    _requireAdmin(actor);
    _check(AccountRules.password(newPassword));
    await _find(id);
    await _setPassword(id, newPassword);
  }

  /// User mengganti password sendiri; wajib benar password lamanya.
  Future<void> changeOwnPassword({
    required AppUser user,
    required String currentPassword,
    required String newPassword,
  }) async {
    _check(AccountRules.password(newPassword));
    final row = await _find(user.id);
    if (!await _hasher.verify(currentPassword, row.passwordHash)) {
      throw const AccountFailure('Password lama salah.');
    }
    if (currentPassword == newPassword) {
      throw const AccountFailure('Password baru harus berbeda dari yang lama.');
    }
    await _setPassword(user.id, newPassword);
  }

  Future<void> delete({required AppUser actor, required int id}) async {
    _requireAdmin(actor);
    if (id == actor.id) {
      throw const AccountFailure('Anda tidak bisa menghapus akun sendiri.');
    }
    // TODO(Langkah 5): tolak hapus jika user sudah punya transaksi penjualan;
    // sarankan nonaktifkan agar riwayat faktur tetap utuh.
    await _db.transaction(() async {
      final current = await _find(id);
      if (_isActiveAdmin(current)) await _ensureAnotherActiveAdmin();
      await _db.usersDao.deleteUser(id);
    });
  }

  Future<void> _setPassword(int id, String password) async {
    final hash = await _hasher.hash(password);
    await _db.usersDao.updateUser(
      id,
      UsersCompanion(passwordHash: Value(hash)),
    );
  }

  Future<UserRow> _find(int id) async {
    final row = await _db.usersDao.findById(id);
    if (row == null) throw const AccountFailure('Akun tidak ditemukan.');
    return row;
  }

  bool _isActiveAdmin(UserRow row) =>
      row.isActive && row.role == UserRole.admin;

  /// Dipanggil sebelum mencabut status admin aktif dari seseorang.
  Future<void> _ensureAnotherActiveAdmin() async {
    if (await _db.usersDao.countActiveAdmins() <= 1) {
      throw const AccountFailure('Harus ada minimal satu admin aktif.');
    }
  }

  void _requireAdmin(AppUser actor) {
    if (!actor.isAdmin) {
      throw const AccountFailure('Hanya admin yang bisa mengelola akun.');
    }
  }

  void _check(String? error) {
    if (error != null) throw AccountFailure(error);
  }
}

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(passwordHasherProvider),
  ),
);
