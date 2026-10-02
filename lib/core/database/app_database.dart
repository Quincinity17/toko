import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../features/auth/domain/user_role.dart';
import '../../features/payments/domain/payment_method.dart';
import 'daos/held_carts_dao.dart';
import 'daos/payment_methods_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/products_dao.dart';
import 'daos/reports_dao.dart';
import 'daos/sales_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/stores_dao.dart';
import 'daos/users_dao.dart';
import 'sample_products.dart';
import 'uuid.dart';
import 'tables/held_carts.dart';
import 'tables/payment_methods.dart';
import 'tables/products.dart';
import 'tables/sales.dart';
import 'tables/stores.dart';
import 'tables/sync.dart';
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
/// - v4: kolom `uuid` di semua tabel yang disinkron, sales.terminal_code,
///   settings, sync_outbox; kuota voucher tidak dipakai lagi
/// - v5: held_carts (transaksi ditahan, lokal saja)
/// - v6: stores, store_products (stok & harga per toko); store_id di users,
///   sales, stock_movements, held_carts; stock_movements.user_id. Data lama
///   masuk ke "Toko Utama".
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
    AppSettings,
    SyncOutbox,
    HeldCarts,
    Stores,
    StoreProducts,
  ],
  daos: [
    UsersDao,
    ProductsDao,
    SalesDao,
    PaymentMethodsDao,
    SettingsDao,
    OutboxDao,
    ReportsDao,
    HeldCartsDao,
    StoresDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openDefault());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await insertSampleProducts(this);
      await _insertDefaultPaymentMethods();
      await _assignDefaultStore();
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
      if (from < 4) {
        // Langkah v4 dibuat idempoten (cek dulu sebelum menambah) karena
        // tabel yang dibuat di cabang v1/v2 di atas sudah memakai definisi
        // terbaru, sedangkan tabel lama belum.
        await m.createTable(appSettings);
        await m.createTable(syncOutbox);
        await m.createIndex(idxSyncOutboxPending);
        await _ensureColumn(m, sales, sales.terminalCode);
        for (final (table, column) in _syncedTables) {
          await _ensureColumn(m, table, column);
          await _backfillUuid(table.actualTableName);
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS '
            'idx_${table.actualTableName}_uuid '
            'ON ${table.actualTableName} (uuid)',
          );
        }
        // Faktur yang dibuat sebelum ada antrian ikut dikirim ke server nanti.
        await customStatement(
          "INSERT INTO sync_outbox (entity, entity_uuid) "
          "SELECT 'sale', uuid FROM sales "
          'WHERE uuid NOT IN (SELECT entity_uuid FROM sync_outbox) '
          'ORDER BY id',
        );
      }
      if (from < 5) {
        // Tidak dibuat di cabang mana pun di atas, jadi aman dibuat di sini.
        await m.createTable(heldCarts);
      }
      if (from < 6) {
        await m.createTable(stores);
        await m.createIndex(idxStoresUuid);
        await m.createTable(storeProducts);
        await m.createIndex(idxStoreProductsUuid);
        // Idempoten: sales/stock_movements/held_carts yang dibuat di cabang
        // lebih awal sudah memakai definisi terbaru (sudah punya store_id).
        await _ensureColumn(m, users, users.storeId);
        await _ensureColumn(m, sales, sales.storeId);
        await _ensureColumn(m, stockMovements, stockMovements.storeId);
        await _ensureColumn(m, stockMovements, stockMovements.userId);
        await _ensureColumn(m, heldCarts, heldCarts.storeId);
        await _assignDefaultStore();
      }
      if (from < 7) {
        // Idempoten: tabel stores dari cabang v6 di atas sudah punya kolomnya.
        await _ensureColumn(m, stores, stores.receiptTemplate);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Tabel yang barisnya akan disinkron dengan server, beserta kolom uuid-nya
  /// (untuk langkah v4; stores & store_products dibuat di v6 sudah ber-uuid).
  List<(TableInfo, GeneratedColumn<String>)> get _syncedTables => [
    (users, users.uuid),
    (categories, categories.uuid),
    (units, units.uuid),
    (products, products.uuid),
    (vouchers, vouchers.uuid),
    (paymentMethods, paymentMethods.uuid),
    (sales, sales.uuid),
    (saleItems, saleItems.uuid),
    (stockMovements, stockMovements.uuid),
  ];

  Future<void> _ensureColumn(
    Migrator m,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    final info = await customSelect(
      'PRAGMA table_info(${table.actualTableName})',
    ).get();
    final exists = info.any((r) => r.read<String>('name') == column.name);
    if (!exists) await m.addColumn(table, column);
  }

  /// Mengisi uuid untuk baris lama yang dibuat sebelum v4.
  Future<void> _backfillUuid(String table) async {
    final rows = await customSelect('SELECT id FROM $table WHERE uuid IS NULL')
        .get();
    for (final r in rows) {
      await customUpdate(
        'UPDATE $table SET uuid = ? WHERE id = ?',
        variables: [
          Variable.withString(newUuid()),
          Variable.withInt(r.read<int>('id')),
        ],
      );
    }
  }

  /// Memastikan ada minimal satu toko, lalu memasukkan data yang belum punya
  /// toko ke toko pertama: akun supervisor/kasir, faktur, riwayat stok,
  /// transaksi tertahan, dan stok barang (dari `products.stock` lama).
  Future<void> _assignDefaultStore() async {
    final first =
        await (select(stores)
              ..orderBy([(s) => OrderingTerm.asc(s.id)])
              ..limit(1))
            .getSingleOrNull();
    final storeId =
        first?.id ??
        await into(stores).insert(StoresCompanion.insert(name: 'Toko Utama'));
    await customStatement(
      "UPDATE users SET store_id = ? WHERE store_id IS NULL AND role != 'admin'",
      [storeId],
    );
    for (final table in ['sales', 'stock_movements', 'held_carts']) {
      await customStatement(
        'UPDATE $table SET store_id = ? WHERE store_id IS NULL',
        [storeId],
      );
    }
    final missing = await customSelect(
      'SELECT id, stock FROM products WHERE id NOT IN '
      '(SELECT product_id FROM store_products WHERE store_id = ?)',
      variables: [Variable.withInt(storeId)],
    ).get();
    await batch((b) {
      for (final r in missing) {
        b.insert(
          storeProducts,
          StoreProductsCompanion.insert(
            storeId: storeId,
            productId: r.read<int>('id'),
            stock: Value(r.read<double>('stock')),
          ),
        );
      }
    });
  }

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
