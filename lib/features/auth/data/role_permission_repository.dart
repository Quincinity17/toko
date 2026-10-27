import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/audit.dart';
import '../domain/app_user.dart';
import '../domain/permission.dart';
import '../domain/user_role.dart';
import '../../sync/data/terminal_repository.dart';

class PermissionFailure implements Exception {
  const PermissionFailure(this.message);

  final String message;

  @override
  String toString() => 'PermissionFailure: $message';
}

/// Hak akses per peran (Pengaturan › Hak Akses Peran). Hanya admin yang
/// mengubah; perubahan berlaku saat akun peran itu login berikutnya.
class RolePermissionRepository {
  RolePermissionRepository(this._db);

  final AppDatabase _db;

  Stream<Map<UserRole, Set<Permission>>> watchAll() =>
      _db.rolePermissionsDao.watchAll();

  /// Menyalakan/mematikan satu hak (beserta ketergantungannya, lihat
  /// [PermissionRules.toggle]).
  Future<void> set({
    required AppUser actor,
    required UserRole role,
    required Permission permission,
    required bool granted,
  }) async {
    _check(actor, role);
    if (await TerminalRepository.masterLockMessage(_db) case final m?) {
      throw PermissionFailure(m);
    }
    await _db.transaction(() async {
      final current = await _db.rolePermissionsDao.permissionsOf(role);
      final next = PermissionRules.toggle(current, permission, granted);
      if (_same(current, next)) return;
      await _db.rolePermissionsDao.replace(role, next);
      await _log(
        actor,
        '${role.label}: ${permission.label} '
        '${granted ? 'diizinkan' : 'dicabut'}',
        role,
        next,
      );
    });
  }

  /// Mengembalikan hak akses [role] ke bawaan.
  Future<void> resetDefaults({
    required AppUser actor,
    required UserRole role,
  }) async {
    _check(actor, role);
    if (await TerminalRepository.masterLockMessage(_db) case final m?) {
      throw PermissionFailure(m);
    }
    await _db.transaction(() async {
      final next = PermissionRules.defaults(role);
      await _db.rolePermissionsDao.replace(role, next);
      await _log(
        actor,
        '${role.label}: hak akses dikembalikan ke bawaan',
        role,
        next,
      );
    });
  }

  static bool _same(Set<Permission> a, Set<Permission> b) =>
      a.length == b.length && a.containsAll(b);

  Future<void> _log(
    AppUser actor,
    String summary,
    UserRole role,
    Set<Permission> now,
  ) => _db.auditDao.append(
    type: AuditType.permissionsChanged,
    summary: summary,
    userId: actor.id,
    userName: actor.fullName,
    data: {
      'role': role.name,
      'permissions': [
        for (final p in Permission.values)
          if (now.contains(p)) p.name,
      ],
    },
  );

  void _check(AppUser actor, UserRole role) {
    if (!actor.isAdmin) {
      throw const PermissionFailure(
        'Hanya admin yang bisa mengatur hak akses peran.',
      );
    }
    if (!PermissionRules.editableRoles.contains(role)) {
      throw const PermissionFailure('Admin selalu punya semua hak akses.');
    }
  }
}

final rolePermissionRepositoryProvider = Provider<RolePermissionRepository>(
  (ref) => RolePermissionRepository(ref.watch(appDatabaseProvider)),
);

final rolePermissionsProvider =
    StreamProvider.autoDispose<Map<UserRole, Set<Permission>>>(
      (ref) => ref.watch(rolePermissionRepositoryProvider).watchAll(),
    );
