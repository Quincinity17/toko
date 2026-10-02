import 'package:drift/drift.dart';

import '../uuid.dart';
import 'products.dart';

/// Toko (cabang). Supervisor dan kasir terikat ke satu toko; admin tidak.
@DataClassName('StoreRow')
@TableIndex(name: 'idx_stores_uuid', columns: {#uuid}, unique: true)
class Stores extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`).
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  TextColumn get name => text().withLength(min: 1, max: 60).unique()();
  TextColumn get address => text().nullable()();

  /// v7: bentuk struk toko ini (JSON `ReceiptTemplate`: HTML + logo).
  /// `null` = template bawaan.
  TextColumn get receiptTemplate => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Data barang per toko: stok toko itu dan harga jual khusus toko.
///
/// Baris dibuat saat pertama dibutuhkan (stok diubah, harga diatur, atau
/// terjual). Tidak ada baris = stok 0 dan harga default barang.
@DataClassName('StoreProductRow')
@TableIndex(name: 'idx_store_products_uuid', columns: {#uuid}, unique: true)
class StoreProducts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`).
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  IntColumn get storeId => integer().references(Stores, #id)();
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();
  RealColumn get stock => real().withDefault(const Constant(0))();

  /// Harga jual khusus toko ini; `null` = harga default `products.selling_price`.
  IntColumn get sellingPrice => integer().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {storeId, productId},
  ];
}
