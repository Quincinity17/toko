import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/audit.dart';
import '../../../core/security/password_hasher.dart';
import '../domain/account_rules.dart';
import '../domain/app_user.dart';
import '../domain/user_role.dart';
import 'auth_repository.dart';
import '../../sync/data/terminal_repository.dart';

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
    int? storeId,
    required String password,
  }) async {
    _requireAdmin(actor);
    await _requireMaster();
    _check(AccountRules.username(username));
    _check(AccountRules.fullName(fullName));
    _check(AccountRules.password(password));

    final normalized = AccountRules.normalizeUsername(username);
    if (await _db.usersDao.findByUsername(normalized) != null) {
      throw AccountFailure('Username "$normalized" sudah dipakai.');
    }
    final store = await _storeFor(role, storeId);

    final hash = await _hasher.hash(password);
    final id = await _db.usersDao.insertUser(
      UsersCompanion.insert(
        username: normalized,
        fullName: fullName.trim(),
        passwordHash: hash,
        role: role,
        storeId: Value(store),
      ),
    );
    await _log(
      actor,
      AuditType.userCreated,
      'Akun baru $normalized (${fullName.trim()}, ${role.label})',
      id,
    );
    return userFromRow((await _db.usersDao.findById(id))!);
  }

  Future<void> _log(
    AppUser actor,
    AuditType type,
    String summary,
    int targetId, [
    Map<String, Object?> extra = const {},
  ]) => _db.auditDao.append(
    type: type,
    summary: summary,
    userId: actor.id,
    userName: actor.fullName,
    data: {'targetUserId': targetId, ...extra},
  );

  /// Mengubah nama, peran, toko, dan status aktif. Username tidak bisa diubah.
  Future<AppUser> update({
    required AppUser actor,
    required int id,
    required String fullName,
    required UserRole role,
    int? storeId,
    required bool isActive,
  }) async {
    _requireAdmin(actor);
    await _requireMaster();
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
      final store = await _storeFor(role, storeId);

      await _db.usersDao.updateUser(
        id,
        UsersCompanion(
          fullName: Value(fullName.trim()),
          role: Value(role),
          storeId: Value(store),
          isActive: Value(isActive),
        ),
      );
      final changes = [
        if (current.fullName != fullName.trim())
          'nama "${current.fullName}" → "${fullName.trim()}"',
        if (current.role != role) 'peran ${current.role.label} → ${role.label}',
        if (current.storeId != store) 'toko diubah',
        if (current.isActive != isActive)
          isActive ? 'diaktifkan' : 'dinonaktifkan',
      ];
      if (changes.isNotEmpty) {
        await _log(
          actor,
          AuditType.userUpdated,
          'Akun ${current.username}: ${changes.join('; ')}',
          id,
          {'changes': changes},
        );
      }
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
    await _requireMaster();
    _check(AccountRules.password(newPassword));
    final row = await _find(id);
    await _setPassword(id, newPassword);
    await _log(
      actor,
      AuditType.userPasswordReset,
      'Reset password akun ${row.username}',
      id,
    );
  }

  /// Admin mengganti password sendiri; wajib benar password lamanya.
  Future<void> changeOwnPassword({
    required AppUser user,
    required String currentPassword,
    required String newPassword,
  }) async {
    // Kebijakan toko: password hanya diganti oleh admin. Kasir minta admin
    // mereset lewat Kelola Akun.
    _requireAdmin(user);
    await _requireMaster();
    _check(AccountRules.password(newPassword));
    final row = await _find(user.id);
    if (!await _hasher.verify(currentPassword, row.passwordHash)) {
      throw const AccountFailure('Password lama salah.');
    }
    if (currentPassword == newPassword) {
      throw const AccountFailure('Password baru harus berbeda dari yang lama.');
    }
    await _setPassword(user.id, newPassword);
    await _log(
      user,
      AuditType.passwordChanged,
      'Ganti password sendiri',
      user.id,
    );
  }

  Future<void> delete({required AppUser actor, required int id}) async {
    _requireAdmin(actor);
    await _requireMaster();
    if (id == actor.id) {
      throw const AccountFailure('Anda tidak bisa menghapus akun sendiri.');
    }
    // Faktur menyimpan id kasir; menghapusnya akan merusak riwayat penjualan.
    if (await _db.salesDao.countByUser(id) > 0) {
      throw const AccountFailure(
        'Akun ini sudah punya transaksi penjualan sehingga tidak bisa dihapus. '
        'Nonaktifkan saja agar riwayat faktur tetap utuh.',
      );
    }
    await _db.transaction(() async {
      final current = await _find(id);
      if (_isActiveAdmin(current)) await _ensureAnotherActiveAdmin();
      await _db.usersDao.deleteUser(id);
      await _log(
        actor,
        AuditType.userDeleted,
        'Hapus akun ${current.username} (${current.fullName})',
        id,
      );
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

  /// Toko yang disimpan untuk [role]: wajib toko aktif untuk supervisor/kasir,
  /// selalu `null` untuk admin.
  Future<int?> _storeFor(UserRole role, int? storeId) async {
    if (!role.needsStore) return null;
    if (storeId == null) {
      throw AccountFailure('Pilih toko untuk ${role.label.toLowerCase()}.');
    }
    final store = await _db.storesDao.findById(storeId);
    if (store == null || !store.isActive) {
      throw const AccountFailure('Toko tidak ditemukan atau sudah nonaktif.');
    }
    return storeId;
  }

  bool _isActiveAdmin(UserRow row) =>
      row.isActive && row.role == UserRole.admin;

  /// Dipanggil sebelum mencabut status admin aktif dari seseorang.
  Future<void> _ensureAnotherActiveAdmin() async {
    if (await _db.usersDao.countActiveAdmins() <= 1) {
      throw const AccountFailure('Harus ada minimal satu admin aktif.');
    }
  }

  /// Data master hanya diubah di komputer server (lihat sinkron).
  Future<void> _requireMaster() async {
    final message = await TerminalRepository.masterLockMessage(_db);
    if (message != null) throw AccountFailure(message);
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
