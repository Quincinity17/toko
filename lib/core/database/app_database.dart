import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/auth/domain/user_role.dart';
import 'daos/products_dao.dart';
import 'daos/sales_dao.dart';
import 'daos/users_dao.dart';
import 'sample_products.dart';
import 'tables/products.dart';
import 'tables/sales.dart';
import 'tables/users.dart';

part 'app_database.g.dart';

/// Database lokal SQLite (drift). Satu instance untuk seluruh aplikasi,
/// dibuat di `main()` dan disuntikkan lewat [appDatabaseProvider].
///
/// Riwayat skema:
/// - v1: users
/// - v2: categories, units, products, sales, sale_items, stock_movements
///   (+ 20 barang contoh)
@DriftDatabase(
  tables: [
    Users,
    Categories,
    Units,
    Products,
    Sales,
    SaleItems,
    StockMovements,
  ],
  daos: [UsersDao, ProductsDao, SalesDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openDefault());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await insertSampleProducts(this);
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(categories);
        await m.createTable(units);
        await m.createTable(products);
        await m.createTable(sales);
        await m.createTable(saleItems);
        await m.createTable(stockMovements);
        await m.createIndex(idxProductsName);
        await m.createIndex(idxSalesDate);
        await insertSampleProducts(this);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// File `toko.sqlite` di folder data aplikasi
  /// (Windows: %APPDATA%\id.toko\toko).
  static QueryExecutor _openDefault() {
    return driftDatabase(
      name: 'toko',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('Di-override di main()'),
);
