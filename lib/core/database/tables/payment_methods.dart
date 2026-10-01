import 'package:drift/drift.dart';

import '../../../features/payments/domain/payment_method.dart';

/// Metode pembayaran yang bisa dipilih kasir (Tunai, QRIS, Transfer, ...).
@DataClassName('PaymentMethodRow')
class PaymentMethods extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 40).unique()();
  TextColumn get kind => textEnum<PaymentKind>()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
