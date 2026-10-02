// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stores_dao.dart';

// ignore_for_file: type=lint
mixin _$StoresDaoMixin on DatabaseAccessor<AppDatabase> {
  $StoresTable get stores => attachedDatabase.stores;
  $CategoriesTable get categories => attachedDatabase.categories;
  $UnitsTable get units => attachedDatabase.units;
  $ProductsTable get products => attachedDatabase.products;
  $StoreProductsTable get storeProducts => attachedDatabase.storeProducts;
  $UsersTable get users => attachedDatabase.users;
  $VouchersTable get vouchers => attachedDatabase.vouchers;
  $PaymentMethodsTable get paymentMethods => attachedDatabase.paymentMethods;
  $SalesTable get sales => attachedDatabase.sales;
  $StockMovementsTable get stockMovements => attachedDatabase.stockMovements;
  StoresDaoManager get managers => StoresDaoManager(this);
}

class StoresDaoManager {
  final _$StoresDaoMixin _db;
  StoresDaoManager(this._db);
  $$StoresTableTableManager get stores =>
      $$StoresTableTableManager(_db.attachedDatabase, _db.stores);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db.attachedDatabase, _db.units);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$StoreProductsTableTableManager get storeProducts =>
      $$StoreProductsTableTableManager(_db.attachedDatabase, _db.storeProducts);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$VouchersTableTableManager get vouchers =>
      $$VouchersTableTableManager(_db.attachedDatabase, _db.vouchers);
  $$PaymentMethodsTableTableManager get paymentMethods =>
      $$PaymentMethodsTableTableManager(
        _db.attachedDatabase,
        _db.paymentMethods,
      );
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
  $$StockMovementsTableTableManager get stockMovements =>
      $$StockMovementsTableTableManager(
        _db.attachedDatabase,
        _db.stockMovements,
      );
}
