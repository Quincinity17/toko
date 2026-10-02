// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_methods_dao.dart';

// ignore_for_file: type=lint
mixin _$PaymentMethodsDaoMixin on DatabaseAccessor<AppDatabase> {
  $PaymentMethodsTable get paymentMethods => attachedDatabase.paymentMethods;
  $StoresTable get stores => attachedDatabase.stores;
  $UsersTable get users => attachedDatabase.users;
  $VouchersTable get vouchers => attachedDatabase.vouchers;
  $SalesTable get sales => attachedDatabase.sales;
  PaymentMethodsDaoManager get managers => PaymentMethodsDaoManager(this);
}

class PaymentMethodsDaoManager {
  final _$PaymentMethodsDaoMixin _db;
  PaymentMethodsDaoManager(this._db);
  $$PaymentMethodsTableTableManager get paymentMethods =>
      $$PaymentMethodsTableTableManager(
        _db.attachedDatabase,
        _db.paymentMethods,
      );
  $$StoresTableTableManager get stores =>
      $$StoresTableTableManager(_db.attachedDatabase, _db.stores);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$VouchersTableTableManager get vouchers =>
      $$VouchersTableTableManager(_db.attachedDatabase, _db.vouchers);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
}
