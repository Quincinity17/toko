import 'package:drift/drift.dart';

import '../uuid.dart';
import 'stores.dart';

@DataClassName('CategoryRow')
@TableIndex(name: 'idx_categories_uuid', columns: {#uuid}, unique: true)
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`). Nullable di skema
  /// karena SQLite tidak bisa menambah kolom NOT NULL ke tabel lama; selalu
  /// terisi lewat clientDefault dan backfill migrasi v4.
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  TextColumn get name => text().withLength(min: 1, max: 60).unique()();
}

@DataClassName('UnitRow')
@TableIndex(name: 'idx_units_uuid', columns: {#uuid}, unique: true)
class Units extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`). Nullable di skema
  /// karena SQLite tidak bisa menambah kolom NOT NULL ke tabel lama; selalu
  /// terisi lewat clientDefault dan backfill migrasi v4.
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  TextColumn get name => text().withLength(min: 1, max: 20).unique()();
}

/// Master barang. Harga dalam Rupiah (INTEGER); stok REAL agar mendukung
/// barang timbangan (kg, liter).
@DataClassName('ProductRow')
@TableIndex(name: 'idx_products_name', columns: {#name})
@TableIndex(name: 'idx_products_uuid', columns: {#uuid}, unique: true)
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`). Nullable di skema
  /// karena SQLite tidak bisa menambah kolom NOT NULL ke tabel lama; selalu
  /// terisi lewat clientDefault dan backfill migrasi v4.
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  TextColumn get code => text().withLength(min: 1, max: 40).unique()();
  TextColumn get barcode =>
      text().withLength(min: 1, max: 40).nullable().unique()();
  TextColumn get name => text().withLength(min: 1, max: 150)();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get unitId => integer().nullable().references(Units, #id)();
  IntColumn get purchasePrice => integer().withDefault(const Constant(0))();

  /// Harga jual default; toko bisa punya harga sendiri (`store_products`).
  IntColumn get sellingPrice => integer().withDefault(const Constant(0))();

  /// Sejak v6 tidak dipakai lagi: stok disimpan per toko di `store_products`.
  /// Kolom dipertahankan (dipindah ke toko pertama saat migrasi).
  RealColumn get stock => real().withDefault(const Constant(0))();
  RealColumn get minStock => real().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// v12: segel (`Sealer`) atas id, kode, harga beli, harga jual, aktif.
  TextColumn get seal => text().nullable()();
}

/// v16: satuan lain sebuah barang (mis. DUS = 24 PCS). Stok tetap disimpan
/// dalam satuan dasar barang; menjual 1 DUS mengurangi stok 24. Harga satuan
/// ini berlaku di semua toko.
@DataClassName('ProductUnitRow')
@TableIndex(name: 'idx_product_units_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_product_units_product', columns: {#productId})
class ProductUnits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();

  /// Nama satuan, huruf besar (DUS, PAK, LUSIN).
  TextColumn get name => text().withLength(min: 1, max: 20)();

  /// Isi satu satuan ini dalam satuan dasar (> 0, bukan 1).
  RealColumn get factor => real()();

  /// Barcode kemasan (opsional, unik di antara semua barcode barang).
  TextColumn get barcode =>
      text().withLength(min: 1, max: 40).nullable().unique()();
  IntColumn get sellingPrice => integer()();

  /// Segel (`Sealer`) atas id, barang, isi, harga.
  TextColumn get seal => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {productId, name},
  ];
}

/// v16: harga grosir/bertingkat satuan dasar barang: beli minimal [minQty]
/// → harga [price] per satuan. v19: [storeId] `null` = berlaku di semua
/// toko; toko yang punya baris sendiri memakai barisnya sendiri saja.
@DataClassName('PriceTierRow')
@TableIndex(name: 'idx_price_tiers_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_price_tiers_product', columns: {#productId})
class PriceTiers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();
  RealColumn get minQty => real()();
  IntColumn get price => integer()();

  /// v19: grosir khusus toko ini; `null` = semua toko.
  IntColumn get storeId => integer().nullable().references(Stores, #id)();

  /// Segel (`Sealer`) atas id, barang, jumlah minimal, harga, toko.
  TextColumn get seal => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {productId, storeId, minQty},
  ];
}

/// v19: harga satuan lain (mis. DUS) khusus satu toko; tanpa baris =
/// harga satuan itu ([ProductUnits.sellingPrice]).
@DataClassName('StoreUnitPriceRow')
@TableIndex(name: 'idx_store_unit_prices_uuid', columns: {#uuid}, unique: true)
class StoreUnitPrices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  IntColumn get storeId => integer().references(Stores, #id)();
  IntColumn get productUnitId =>
      integer().references(ProductUnits, #id, onDelete: KeyAction.cascade)();
  IntColumn get sellingPrice => integer()();

  /// Segel (`Sealer`) atas toko, satuan, harga.
  TextColumn get seal => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {storeId, productUnitId},
  ];
}
