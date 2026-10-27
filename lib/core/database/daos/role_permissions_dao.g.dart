// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_permissions_dao.dart';

// ignore_for_file: type=lint
mixin _$RolePermissionsDaoMixin on DatabaseAccessor<AppDatabase> {
  $RolePermissionsTable get rolePermissions => attachedDatabase.rolePermissions;
  RolePermissionsDaoManager get managers => RolePermissionsDaoManager(this);
}

class RolePermissionsDaoManager {
  final _$RolePermissionsDaoMixin _db;
  RolePermissionsDaoManager(this._db);
  $$RolePermissionsTableTableManager get rolePermissions =>
      $$RolePermissionsTableTableManager(
        _db.attachedDatabase,
        _db.rolePermissions,
      );
}
