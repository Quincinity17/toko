import 'package:drift/drift.dart';

import '../uuid.dart';
import 'payment_methods.dart';
import 'products.dart';
import 'stores.dart';
import 'users.dart';
import 'vouchers.dart';

/// Faktur penjualan. Semua nominal dalam Rupiah.
@DataClassName('SaleRow')
@TableIndex(name: 'idx_sales_date', columns: {#saleDate})
@TableIndex(name: 'idx_sales_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_sales_return_of', columns: {#returnOfId})
class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`). Nullable di skema
  /// karena SQLite tidak bisa menambah kolom NOT NULL ke tabel lama; selalu
  /// terisi lewat clientDefault dan backfill migrasi v4.
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();

  /// Sejak v4: `INV-{kode terminal}-YYYYMMDD-0001`, urut per terminal per hari.
  /// Faktur lama: INV-YYYYMMDD-0001.
  TextColumn get invoiceNo => text().unique()();

  /// v4: kode terminal (komputer) yang membuat faktur, mis. `K01`.
  TextColumn get terminalCode => text().nullable()();

  /// v6: toko tempat transaksi. Faktur lama diisi toko pertama saat migrasi.
  IntColumn get storeId => integer().nullable().references(Stores, #id)();
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

  /// v11: nota retur (`RET-…`) = faktur bernilai negatif yang menunjuk faktur
  /// asal. Retur/batal tidak mengubah faktur asal; laporan otomatis
  /// terpotong karena total & qty nota retur negatif. `null` = penjualan.
  IntColumn get returnOfId => integer().nullable().references(Sales, #id)();

  /// v11: alasan retur/batal (wajib diisi untuk nota retur).
  TextColumn get returnReason => text().nullable()();

  /// v15: faktur penukaran barang = penjualan baru yang dibayar sebagian
  /// dengan kredit dari nota retur ini (`RET-…`). Kredit = −total nota retur.
  /// `SET NULL` supaya penghapusan riwayat lama tidak terhalang.
  IntColumn get exchangeOfId => integer().nullable().references(
    Sales,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Baris faktur. Kode, nama, satuan, dan harga disalin saat transaksi supaya
/// faktur lama tidak berubah bila data barang diedit.
@DataClassName('SaleItemRow')
@TableIndex(name: 'idx_sale_items_uuid', columns: {#uuid}, unique: true)
class SaleItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`). Nullable di skema
  /// karena SQLite tidak bisa menambah kolom NOT NULL ke tabel lama; selalu
  /// terisi lewat clientDefault dan backfill migrasi v4.
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
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

  /// v11: baris nota retur → baris faktur asal yang dikembalikan (qty &
  /// subtotal negatif). `null` = baris penjualan.
  IntColumn get returnOfItemId => integer().nullable()();

  /// v16: isi satu [unitName] dalam satuan dasar barang (1 = satuan dasar,
  /// 24 = DUS isi 24). Stok berubah [qty] × [unitFactor]; [purchasePrice]
  /// sudah per satuan yang dijual.
  RealColumn get unitFactor => real().withDefault(const Constant(1))();
}

/// v16: pembayaran terpisah (split payment): satu faktur dibayar dengan
/// lebih dari satu metode. Hanya diisi untuk faktur yang memakai ≥ 2 metode
/// (dan nota returnya); faktur biasa cukup `sales.payment_method_id`.
/// [amount] = nilai yang masuk ke metode itu (tunai: setelah kembalian),
/// jumlahnya = `sales.total`.
@DataClassName('SalePaymentRow')
@TableIndex(name: 'idx_sale_payments_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_sale_payments_sale', columns: {#saleId})
class SalePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  IntColumn get saleId =>
      integer().references(Sales, #id, onDelete: KeyAction.cascade)();
  IntColumn get paymentMethodId =>
      integer().nullable().references(PaymentMethods, #id)();

  /// Nama metode saat transaksi (salinan).
  TextColumn get methodName => text()();
  BoolColumn get isCash => boolean().withDefault(const Constant(false))();
  IntColumn get amount => integer()();

  /// Tunai: uang yang diterima (sebelum kembalian); non-tunai = [amount].
  IntColumn get tendered => integer()();
  TextColumn get ref => text().nullable()();
}

/// `saleReturn` (v11): barang kembali karena retur/batal faktur.
enum StockMovementType { sale, import, adjust, saleReturn }

/// Riwayat keluar-masuk stok (penjualan, import, penyesuaian).
@DataClassName('StockMovementRow')
@TableIndex(name: 'idx_stock_movements_uuid', columns: {#uuid}, unique: true)
class StockMovements extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`). Nullable di skema
  /// karena SQLite tidak bisa menambah kolom NOT NULL ke tabel lama; selalu
  /// terisi lewat clientDefault dan backfill migrasi v4.
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  IntColumn get productId => integer().references(Products, #id)();

  /// v6: stok toko mana yang berubah.
  IntColumn get storeId => integer().nullable().references(Stores, #id)();

  /// v6: user yang mengubah (kasir saat menjual, admin/supervisor saat
  /// menyesuaikan). Riwayat lama: `null`.
  IntColumn get userId => integer().nullable().references(Users, #id)();
  TextColumn get type => textEnum<StockMovementType>()();

  /// Negatif = stok berkurang.
  RealColumn get qtyChange => real()();

  /// Id sumber, misalnya `sales.id` untuk penjualan.
  IntColumn get refId => integer().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// v19: promo yang dijalankan dari Laporan › Saran Promo (ubah harga barang
/// / buat voucher), untuk membandingkan penjualan sebelum & sesudahnya.
/// Lokal per komputer (tidak disinkron).
@DataClassName('PromoActionRow')
class PromoActions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Nama `PromoKind`.
  TextColumn get kind => text()();
  TextColumn get title => text()();
  IntColumn get productId => integer().nullable().references(
    Products,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get voucherCode => text().nullable()();
  IntColumn get storeId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
}
