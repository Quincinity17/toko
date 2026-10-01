// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reports_dao.dart';

// ignore_for_file: type=lint
mixin _$ReportsDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsersTable get users => attachedDatabase.users;
  $VouchersTable get vouchers => attachedDatabase.vouchers;
  $PaymentMethodsTable get paymentMethods => attachedDatabase.paymentMethods;
  $SalesTable get sales => attachedDatabase.sales;
  $CategoriesTable get categories => attachedDatabase.categories;
  $UnitsTable get units => attachedDatabase.units;
  $ProductsTable get products => attachedDatabase.products;
  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
  ReportsDaoManager get managers => ReportsDaoManager(this);
}

class ReportsDaoManager {
  final _$ReportsDaoMixin _db;
  ReportsDaoManager(this._db);
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
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$UnitsTableTableManager get units =>
      $$UnitsTableTableManager(_db.attachedDatabase, _db.units);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$SaleItemsTableTableManager get saleItems =>
      $$SaleItemsTableTableManager(_db.attachedDatabase, _db.saleItems);
}
