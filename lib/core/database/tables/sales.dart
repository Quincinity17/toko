import 'package:drift/drift.dart';

import 'payment_methods.dart';
import 'products.dart';
import 'users.dart';
import 'vouchers.dart';

/// Faktur penjualan. Semua nominal dalam Rupiah.
@DataClassName('SaleRow')
@TableIndex(name: 'idx_sales_date', columns: {#saleDate})
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Format INV-YYYYMMDD-0001, urut per hari.
  TextColumn get invoiceNo => text().unique()();
  DateTimeColumn get saleDate => dateTime()();
  IntColumn get userId => integer().references(Users, #id)();

  /// Jumlah baris barang, untuk daftar transaksi tanpa query tambahan.
  IntColumn get itemCount => integer()();

  /// Total semua baris setelah potongan per barang.
  IntColumn get subtotal => integer()();

  /// Sejak v3 tidak diisi lagi (potongan manual diganti voucher); tetap ada
  /// untuk faktur lama.
  RealColumn get discountPercent => real().nullable()();

  /// Potongan dalam Rupiah. Sejak v3 berasal dari voucher.
  IntColumn get discount => integer().withDefault(const Constant(0))();

  /// v3: voucher yang dipakai (kode disalin agar faktur tetap terbaca).
  IntColumn get voucherId => integer().nullable().references(Vouchers, #id)();
  TextColumn get voucherCode => text().nullable()();
  IntColumn get total => integer()();
  IntColumn get paid => integer()();
  IntColumn get changeAmount => integer()();

  /// Nama metode pembayaran saat transaksi (salinan).
  TextColumn get paymentMethod => text().withDefault(const Constant('tunai'))();

  /// v3: metode pembayaran dan nomor referensi (QRIS/transfer/kartu).
  IntColumn get paymentMethodId =>
      integer().nullable().references(PaymentMethods, #id)();
  TextColumn get paymentRef => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Baris faktur. Kode, nama, satuan, dan harga disalin saat transaksi supaya
/// faktur lama tidak berubah bila data barang diedit.
@DataClassName('SaleItemRow')
class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get productCode => text()();
  TextColumn get productName => text()();
  TextColumn get unitName => text().nullable()();
  RealColumn get qty => real()();
  IntColumn get price => integer()();

  /// Sejak v3 selalu 0 (potongan per barang dihapus); tetap ada untuk faktur lama.
  RealColumn get discountPercent => real().withDefault(const Constant(0))();
  IntColumn get purchasePrice => integer()();
  IntColumn get subtotal => integer()();
}

enum StockMovementType { sale, import, adjust }

/// Riwayat keluar-masuk stok (penjualan, import, penyesuaian).
@DataClassName('StockMovementRow')
class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  TextColumn get type => textEnum<StockMovementType>()();

  /// Negatif = stok berkurang.
  RealColumn get qtyChange => real()();

  /// Id sumber, misalnya `sales.id` untuk penjualan.
  IntColumn get refId => integer().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
