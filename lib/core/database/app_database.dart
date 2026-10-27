import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/user_role.dart';
import '../../features/payments/domain/payment_method.dart';
import '../security/device_keys.dart';
import '../security/sealer.dart';
import 'daos/audit_dao.dart';
import 'daos/held_carts_dao.dart';
import 'daos/payment_methods_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/products_dao.dart';
import 'daos/role_permissions_dao.dart';
import 'daos/reports_dao.dart';
import 'daos/sales_dao.dart';
import 'daos/seals_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/stores_dao.dart';
import 'daos/tags_dao.dart';
import 'daos/users_dao.dart';
import 'daos/vouchers_dao.dart';
import '../../features/sync/data/sync_schema.dart';
import '../../sync_protocol/sync_protocol.dart';
import 'sample_products.dart';
import 'uuid.dart';
import 'tables/audit.dart';
import 'tables/held_carts.dart';
import 'tables/payment_methods.dart';
import 'tables/products.dart';
import 'tables/role_permissions.dart';
import 'tables/sales.dart';
import 'tables/stores.dart';
import 'tables/sync.dart';
import 'tables/tags.dart';
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
/// - v7–v15: lihat CLAUDE.md (Skema database).
/// - v16: product_units (multi-satuan), price_tiers (harga grosir),
///   sale_payments (split payment), sale_items.unit_factor
/// - v17: tags.code_prefix (awalan barcode otomatis per kategori)
/// - v18: remote_audit_log (catatan aktivitas komputer lain, di master)
/// - v19: store_unit_prices, price_tiers.store_id (harga per toko),
///   tags.code_digits, promo_actions
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
    Tags,
    ProductTags,
    AuditLog,
    RolePermissions,
    ProductUnits,
    PriceTiers,
    SalePayments,
    RemoteAuditLog,
    StoreUnitPrices,
    PromoActions,
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
    TagsDao,
    StoresDao,
    SealsDao,
    AuditDao,
    VouchersDao,
    RolePermissionsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Di aplikasi dibuka lewat `openDeviceDatabase()` (terenkripsi, [keys]
  /// dari perangkat); tes memakai `NativeDatabase.memory()` dan kunci segel
  /// tetap.
  AppDatabase(super.executor, {this.keys})
    : sealer = Sealer((keys ?? DeviceKeys.forTests()).sealKey);

  /// Kunci perangkat; `null` = database tidak dienkripsi (tes).
  final DeviceKeys? keys;

  /// Segel data & catatan aktivitas (lihat [SealsDao], [AuditDao]).
  final Sealer sealer;

  /// Versi skema sekarang (juga dipakai pemeriksa file backup).
  static const currentSchemaVersion = 19;

  @override
  int get schemaVersion => currentSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await insertSampleProducts(this);
      await _insertDefaultPaymentMethods();
      await _assignDefaultStore();
      await insertSampleTags(this);
      await _categoriesToTags();
      await rolePermissionsDao.insertDefaults();
      await _baselineSeals('Database baru');
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
      if (from < 8) {
        // Tidak dibuat di cabang mana pun di atas, jadi aman dibuat di sini.
        await m.createTable(tags);
        await m.createIndex(idxTagsUuid);
        await m.createTable(productTags);
        await m.createIndex(idxProductTagsUuid);
        await m.createIndex(idxProductTagsTag);
      }
      if (from < 9) {
        // Data saja (tanpa ubah skema): tag contoh untuk barang contoh, hanya
        // bila belum ada tag sama sekali.
        await insertSampleTags(this);
      }
      if (from < 10) {
        // Kategori & tag dilebur jadi satu konsep "Kategori" (keputusan
        // user): kategori lama tiap barang menjadi tag barang itu.
        await _categoriesToTags();
      }
      if (from < 11) {
        // Retur/batal faktur = nota retur bernilai negatif. Idempoten: tabel
        // sales/sale_items dari cabang v1 di atas sudah punya kolomnya.
        await _ensureColumn(m, sales, sales.returnOfId);
        await _ensureColumn(m, sales, sales.returnReason);
        await _ensureColumn(m, saleItems, saleItems.returnOfItemId);
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_sales_return_of '
          'ON sales (return_of_id)',
        );
      }
      if (from < 12) {
        // Catatan aktivitas berantai + segel data (keamanan). Idempoten:
        // tabel dari cabang awal sudah punya kolom seal.
        await m.createTable(auditLog);
        await m.createIndex(idxAuditLogCreated);
        await _ensureColumn(m, users, users.seal);
        await _ensureColumn(m, products, products.seal);
        await _ensureColumn(m, storeProducts, storeProducts.seal);
        await _baselineSeals('Pembaruan aplikasi (v12)');
      }
      if (from < 13) {
        // Voucher promo dihidupkan lagi, bisa dibatasi ke satu toko.
        // Idempoten: tabel vouchers dari cabang v1/v2 sudah punya kolomnya.
        await _ensureColumn(m, vouchers, vouchers.storeId);
      }
      if (from < 14) {
        // Hak akses per peran (bisa diatur admin). Tidak dibuat di cabang
        // mana pun di atas; bawaan = perilaku sebelumnya.
        await m.createTable(rolePermissions);
        await m.createIndex(idxRolePermissionsUuid);
        await rolePermissionsDao.insertDefaults();
      }
      if (from < 15) {
        // Tukar barang. Idempoten: tabel sales dari cabang v1 di atas sudah
        // punya kolomnya.
        await _ensureColumn(m, sales, sales.exchangeOfId);
      }
      if (from < 16) {
        // Multi-satuan, harga grosir, split payment. Tabel baru tidak dibuat
        // di cabang mana pun di atas; kolom sale_items idempoten (cabang v1
        // sudah memakai definisi terbaru).
        await m.createTable(productUnits);
        await m.createIndex(idxProductUnitsUuid);
        await m.createIndex(idxProductUnitsProduct);
        await m.createTable(priceTiers);
        await m.createIndex(idxPriceTiersUuid);
        await m.createIndex(idxPriceTiersProduct);
        await m.createTable(salePayments);
        await m.createIndex(idxSalePaymentsUuid);
        await m.createIndex(idxSalePaymentsSale);
        await _ensureColumn(m, saleItems, saleItems.unitFactor);
      }
      if (from < 17) {
        // Awalan barcode per kategori. Idempoten: tabel tags dari cabang v8
        // sudah memakai definisi terbaru.
        await _ensureColumn(m, tags, tags.codePrefix);
      }
      if (from < 18) {
        // Catatan aktivitas komputer cabang (diterima master lewat sinkron).
        await m.createTable(remoteAuditLog);
        await m.createIndex(idxRemoteAuditUuid);
        await m.createIndex(idxRemoteAuditCreated);
      }
      if (from < 19) {
        // Harga satuan lain & grosir per toko, digit barcode per kategori,
        // riwayat promo. price_tiers dibuat ulang (kunci unik ikut toko);
        // tabel dari cabang v16 di atas sudah memakai definisi terbaru.
        final info = await customSelect('PRAGMA table_info(price_tiers)').get();
        if (!info.any((r) => r.read<String>('name') == 'store_id')) {
          await m.alterTable(
            TableMigration(priceTiers, newColumns: [priceTiers.storeId]),
          );
        }
        await m.createTable(storeUnitPrices);
        await m.createIndex(idxStoreUnitPricesUuid);
        await m.createTable(promoActions);
        await _ensureColumn(m, tags, tags.codeDigits);
        // Kolom segel harga grosir bertambah (toko).
        await sealsDao.resealAll();
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      // Sudah disambungkan ke server: perubahan data diantrikan (trigger
      // sementara, per koneksi).
      final token = await customSelect(
        "SELECT value FROM settings WHERE key = 'sync.token'",
      ).getSingleOrNull();
      if ((token?.read<String>('value') ?? '').isNotEmpty) {
        for (final sql in syncTriggerStatements()) {
          await customStatement(sql);
        }
      }
    },
  );

  /// v10: kategori lama (`products.category_id`, satu per barang) dipasang
  /// sebagai tag barang itu. Nama yang sudah ada sebagai tag dipakai ulang
  /// (tanpa peduli huruf besar); kategori baru diberi warna bergiliran.
  /// `categories`/`category_id` tetap ada di skema tetapi tidak dipakai lagi.
  Future<void> _categoriesToTags() async {
    const palette = [
      'blue', 'green', 'orange', 'purple', 'teal', 'pink', 'indigo', //
      'brown', 'mint', 'red', 'cyan', 'lime', 'yellow', 'gray', 'black',
    ];
    final rows = await customSelect(
      'SELECT p.id AS product_id, c.name AS name FROM products p '
      'JOIN categories c ON c.id = p.category_id',
      readsFrom: {products, categories},
    ).get();
    final tagIds = <String, int>{};
    for (final t in await select(tags).get()) {
      tagIds[t.name.toLowerCase()] = t.id;
    }
    var next = 0;
    for (final r in rows) {
      final name = r.read<String>('name').trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      final id = tagIds[key] ??= await into(tags).insert(
        TagsCompanion.insert(
          name: name.length > 30 ? name.substring(0, 30) : name,
          color: Value(palette[next++ % palette.length]),
        ),
      );
      await into(productTags).insert(
        ProductTagsCompanion.insert(
          productId: r.read<int>('product_id'),
          tagId: id,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

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
  /// Menyegel semua baris dan memulai rantai catatan aktivitas (database
  /// baru, migrasi v12, setelah memulihkan backup).
  Future<void> _baselineSeals(String reason) async {
    await sealsDao.resealAll();
    await auditDao.append(
      type: AuditType.sealsRebuilt,
      summary: 'Segel data dibuat: $reason',
    );
  }
}

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('Di-override di main()'),
);
