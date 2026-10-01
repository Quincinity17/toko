import 'package:drift/drift.dart';

import '../../../features/vouchers/domain/voucher.dart';

/// Voucher potongan yang dipakai kasir lewat kode.
@DataClassName('VoucherRow')
class Vouchers extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Huruf besar, mis. `HEMAT10`.
  TextColumn get code => text().withLength(min: 3, max: 20).unique()();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get type => textEnum<VoucherType>()();

  /// Persen (0–100) atau nominal Rupiah, sesuai [type].
  RealColumn get value => real()();

  /// Batas potongan untuk voucher persen (null = tanpa batas).
  IntColumn get maxDiscount => integer().nullable()();
  IntColumn get minPurchase => integer().withDefault(const Constant(0))();

  /// Tanggal (tanpa jam). Berlaku sejak awal [startDate] s.d. akhir [endDate].
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();

  /// Batas total pemakaian (null = tanpa batas).
  IntColumn get quota => integer().nullable()();
  IntColumn get usedCount => integer().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
