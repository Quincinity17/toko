// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'seals_dao.dart';

// ignore_for_file: type=lint
mixin _$SealsDaoMixin on DatabaseAccessor<AppDatabase> {
  $StoresTable get stores => attachedDatabase.stores;
  $UsersTable get users => attachedDatabase.users;
  $CategoriesTable get categories => attachedDatabase.categories;
  $UnitsTable get units => attachedDatabase.units;
  $ProductsTable get products => attachedDatabase.products;
  $StoreProductsTable get storeProducts => attachedDatabase.storeProducts;
  SealsDaoManager get managers => SealsDaoManager(this);
}

class SealsDaoManager {
  final _$SealsDaoMixin _db;
  SealsDaoManager(this._db);
  $$StoresTableTableManager get stores =>
      $$StoresTableTableManager(_db.attachedDatabase, _db.stores);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db.attachedDatabase, _db.units);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$StoreProductsTableTableManager get storeProducts =>
      $$StoreProductsTableTableManager(_db.attachedDatabase, _db.storeProducts);
}
