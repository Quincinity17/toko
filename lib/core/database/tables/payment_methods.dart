import 'package:drift/drift.dart';

import '../../../features/payments/domain/payment_method.dart';
import '../uuid.dart';

/// Metode pembayaran yang bisa dipilih kasir (Tunai, QRIS, Transfer, ...).
@DataClassName('PaymentMethodRow')
@TableIndex(name: 'idx_payment_methods_uuid', columns: {#uuid}, unique: true)
class PaymentMethods extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`). Nullable di skema
  /// karena SQLite tidak bisa menambah kolom NOT NULL ke tabel lama; selalu
  /// terisi lewat clientDefault dan backfill migrasi v4.
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  TextColumn get name => text().withLength(min: 1, max: 40).unique()();
  TextColumn get kind => textEnum<PaymentKind>()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
