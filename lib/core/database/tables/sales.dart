import 'package:drift/drift.dart';

import 'products.dart';
import 'users.dart';

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

  /// Potongan per transaksi yang dipakai. Jika diisi persen, [discountPercent]
  /// menyimpan persennya dan [discount] hasil perhitungannya.
  RealColumn get discountPercent => real().nullable()();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  IntColumn get total => integer()();
  IntColumn get paid => integer()();
  IntColumn get changeAmount => integer()();
  TextColumn get paymentMethod => text().withDefault(const Constant('tunai'))();
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
