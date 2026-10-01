import 'package:drift/drift.dart';

import '../uuid.dart';

/// Jenis voucher. Disimpan sebagai nama enum.
enum VoucherType { percent, amount }

/// Voucher potongan. **Fitur voucher sudah dihapus dari aplikasi** (keputusan
/// user, Okt 2026); tabel ini dibiarkan agar skema database tidak berubah dan
/// fitur bisa dihidupkan lagi. Tidak ada kode yang membaca/menulis tabel ini.
@DataClassName('VoucherRow')
@TableIndex(name: 'idx_vouchers_uuid', columns: {#uuid}, unique: true)
class Vouchers extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`). Nullable di skema
  /// karena SQLite tidak bisa menambah kolom NOT NULL ke tabel lama; selalu
  /// terisi lewat clientDefault dan backfill migrasi v4.
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();

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

  // Catatan: kolom `quota` dan `used_count` (v3) dihapus di v4 atas
  // permintaan user (voucher cukup aktif/nonaktif). Pada database lama
  // kolomnya masih ada tetapi tidak dipakai.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
