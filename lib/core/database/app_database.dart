import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/auth/domain/user_role.dart';
import '../../features/payments/domain/payment_method.dart';
import '../../features/vouchers/domain/voucher.dart';
import 'daos/payment_methods_dao.dart';
import 'daos/products_dao.dart';
import 'daos/sales_dao.dart';
import 'daos/users_dao.dart';
import 'daos/vouchers_dao.dart';
import 'sample_products.dart';
import 'tables/payment_methods.dart';
import 'tables/products.dart';
import 'tables/sales.dart';
import 'tables/users.dart';
import 'tables/vouchers.dart';

part 'app_database.g.dart';

/// Database lokal SQLite (drift). Satu instance untuk seluruh aplikasi,
/// dibuat di `main()` dan disuntikkan lewat [appDatabaseProvider].
///
/// Riwayat skema:
/// - v1: users
/// - v2: categories, units, products, sales, sale_items, stock_movements
///   (+ 20 barang contoh)
/// - v3: vouchers, payment_methods (+ 4 metode bawaan); sales.voucher_id,
///   voucher_code, payment_method_id, payment_ref
@DriftDatabase(
  tables: [
    Users,
    Categories,
    Units,
    Products,
    Vouchers,
    PaymentMethods,
    Sales,
    SaleItems,
    StockMovements,
  ],
  daos: [UsersDao, ProductsDao, SalesDao, VouchersDao, PaymentMethodsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openDefault());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await insertSampleProducts(this);
      await _insertDefaultPaymentMethods();
    },
    onUpgrade: (m, from, to) async {
      // Catatan: createTable selalu memakai definisi tabel TERBARU. Karena itu
      // cabang v1 membuat semua tabel baru sekaligus, sedangkan cabang v2 hanya
      // menambah yang belum ada (agar kolom tidak ditambahkan dua kali).
      if (from < 2) {
        await m.createTable(categories);
        await m.createTable(units);
        await m.createTable(products);
        await m.createTable(vouchers);
        await m.createTable(paymentMethods);
        await m.createTable(sales);
        await m.createTable(saleItems);
        await m.createTable(stockMovements);
        await m.createIndex(idxProductsName);
        await m.createIndex(idxSalesDate);
        await insertSampleProducts(this);
        await _insertDefaultPaymentMethods();
      } else if (from < 3) {
        await m.createTable(vouchers);
        await m.createTable(paymentMethods);
        await m.addColumn(sales, sales.voucherId);
        await m.addColumn(sales, sales.voucherCode);
        await m.addColumn(sales, sales.paymentMethodId);
        await m.addColumn(sales, sales.paymentRef);
        await _insertDefaultPaymentMethods();
        // Faktur lama dibayar tunai.
        await customStatement(
          "UPDATE sales SET payment_method = 'Tunai', payment_method_id = "
          "(SELECT id FROM payment_methods WHERE name = 'Tunai')",
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _insertDefaultPaymentMethods() async {
    const defaults = [
      ('Tunai', PaymentKind.cash),
      ('QRIS', PaymentKind.nonCash),
      ('Transfer Bank', PaymentKind.nonCash),
      ('Kartu Debit/Kredit', PaymentKind.nonCash),
    ];
    await batch((b) {
      for (final (i, (name, kind)) in defaults.indexed) {
        b.insert(
          paymentMethods,
          PaymentMethodsCompanion.insert(
            name: name,
            kind: kind,
            sortOrder: Value(i + 1),
          ),
        );
      }
    });
  }

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
