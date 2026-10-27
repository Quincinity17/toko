import 'package:drift/drift.dart';

import '../../../features/auth/domain/permission.dart';
import '../../../features/auth/domain/user_role.dart';
import '../app_database.dart';
import '../tables/role_permissions.dart';

part 'role_permissions_dao.g.dart';

@DriftAccessor(tables: [RolePermissions])
class RolePermissionsDao extends DatabaseAccessor<AppDatabase>
    with _$RolePermissionsDaoMixin {
  RolePermissionsDao(super.attachedDatabase);

  /// Kolom yang disegel (lihat `SealsDao`).
  static List<Object?> fields(RolePermissionRow r) => [r.role, r.permission];

  bool _valid(RolePermissionRow r) =>
      attachedDatabase.sealer.verify(r.seal, fields(r));

  Map<UserRole, Set<Permission>> _group(List<RolePermissionRow> rows) {
    final out = {
      for (final r in PermissionRules.editableRoles) r: <Permission>{},
    };
    for (final r in rows) {
      final p = Permission.byName(r.permission);
      if (p != null && _valid(r) && out.containsKey(r.role)) {
        out[r.role]!.add(p);
      }
    }
    return out;
  }

  /// Hak akses sah per peran (supervisor & kasir).
  Stream<Map<UserRole, Set<Permission>>> watchAll() =>
      select(rolePermissions).watch().map(_group);

  Future<Set<Permission>> permissionsOf(UserRole role) async {
    final rows = await (select(
      rolePermissions,
    )..where((t) => t.role.equalsValue(role))).get();
    return _group(rows)[role] ?? const {};
  }

  /// Mengganti seluruh hak akses [role] (dipanggil di dalam transaksi).
  Future<void> replace(UserRole role, Set<Permission> permissions) async {
    await (delete(
      rolePermissions,
    )..where((t) => t.role.equalsValue(role))).go();
    for (final p in permissions) {
      await into(rolePermissions).insert(
        RolePermissionsCompanion.insert(
          role: role,
          permission: p.name,
          seal: Value(attachedDatabase.sealer.seal([role, p.name])),
        ),
      );
    }
  }

  /// Hak akses bawaan (database baru & migrasi v14).
  Future<void> insertDefaults() async {
    for (final role in PermissionRules.editableRoles) {
      await replace(role, PermissionRules.defaults(role));
    }
  }

  Future<List<RolePermissionRow>> all() => select(rolePermissions).get();
}
