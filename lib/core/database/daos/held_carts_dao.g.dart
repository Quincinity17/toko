// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'held_carts_dao.dart';

// ignore_for_file: type=lint
mixin _$HeldCartsDaoMixin on DatabaseAccessor<AppDatabase> {
  $StoresTable get stores => attachedDatabase.stores;
  $UsersTable get users => attachedDatabase.users;
  $HeldCartsTable get heldCarts => attachedDatabase.heldCarts;
  HeldCartsDaoManager get managers => HeldCartsDaoManager(this);
}

class HeldCartsDaoManager {
  final _$HeldCartsDaoMixin _db;
  HeldCartsDaoManager(this._db);
  $$StoresTableTableManager get stores =>
      $$StoresTableTableManager(_db.attachedDatabase, _db.stores);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$HeldCartsTableTableManager get heldCarts =>
      $$HeldCartsTableTableManager(_db.attachedDatabase, _db.heldCarts);
}
