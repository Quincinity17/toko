// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vouchers_dao.dart';

// ignore_for_file: type=lint
mixin _$VouchersDaoMixin on DatabaseAccessor<AppDatabase> {
  $StoresTable get stores => attachedDatabase.stores;
  $VouchersTable get vouchers => attachedDatabase.vouchers;
  $UsersTable get users => attachedDatabase.users;
  $PaymentMethodsTable get paymentMethods => attachedDatabase.paymentMethods;
  $SalesTable get sales => attachedDatabase.sales;
  VouchersDaoManager get managers => VouchersDaoManager(this);
}

class VouchersDaoManager {
  final _$VouchersDaoMixin _db;
  VouchersDaoManager(this._db);
  $$StoresTableTableManager get stores =>
      $$StoresTableTableManager(_db.attachedDatabase, _db.stores);
  $$VouchersTableTableManager get vouchers =>
      $$VouchersTableTableManager(_db.attachedDatabase, _db.vouchers);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$PaymentMethodsTableTableManager get paymentMethods =>
      $$PaymentMethodsTableTableManager(
        _db.attachedDatabase,
        _db.paymentMethods,
      );
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
}
