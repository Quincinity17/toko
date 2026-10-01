import 'package:drift/drift.dart';

@DataClassName('CategoryRow')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60).unique()();
}

@DataClassName('UnitRow')
class Units extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 20).unique()();
}

/// Master barang. Harga dalam Rupiah (INTEGER); stok REAL agar mendukung
/// barang timbangan (kg, liter).
@DataClassName('ProductRow')
@TableIndex(name: 'idx_products_name', columns: {#name})
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(min: 1, max: 40).unique()();
  TextColumn get barcode =>
      text().withLength(min: 1, max: 40).nullable().unique()();
  TextColumn get name => text().withLength(min: 1, max: 150)();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get unitId => integer().nullable().references(Units, #id)();
  IntColumn get purchasePrice => integer().withDefault(const Constant(0))();
  IntColumn get sellingPrice => integer().withDefault(const Constant(0))();
  RealColumn get stock => real().withDefault(const Constant(0))();
  RealColumn get minStock => real().withDefault(const Constant(0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
