import 'package:drift/drift.dart';

import '../uuid.dart';
import 'products.dart';

/// v8: tag jenis barang (mis. Mainan, Boneka, Alat Tulis). Satu barang bisa
/// punya banyak tag. Dikelola admin di Pengaturan › Kelola Tag.
@DataClassName('TagRow')
@TableIndex(name: 'idx_tags_uuid', columns: {#uuid}, unique: true)
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`).
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();
  TextColumn get name => text().withLength(min: 1, max: 30).unique()();

  /// Nama warna `TagColor` (blue, pink, …).
  TextColumn get color => text().withDefault(const Constant('blue'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// v8: tag yang dipasang di barang (banyak-ke-banyak).
@DataClassName('ProductTagRow')
@TableIndex(name: 'idx_product_tags_uuid', columns: {#uuid}, unique: true)
@TableIndex(name: 'idx_product_tags_tag', columns: {#tagId})
class ProductTags extends Table {
  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId =>
      integer().references(Tags, #id, onDelete: KeyAction.cascade)();

  /// ID global untuk sinkronisasi (lihat `uuid.dart`).
  TextColumn get uuid => text().nullable().clientDefault(newUuid)();

  @override
  Set<Column> get primaryKey => {productId, tagId};
}
