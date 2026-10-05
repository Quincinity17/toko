import 'package:drift/drift.dart';

import '../app_database.dart';
import '../uuid.dart';
import '../tables/products.dart';
import '../tables/sales.dart';
import '../tables/stores.dart';
import '../tables/users.dart';

part 'stores_dao.g.dart';

@DriftAccessor(
  tables: [Stores, StoreProducts, Products, Users, Sales, StockMovements],
)
class StoresDao extends DatabaseAccessor<AppDatabase> with _$StoresDaoMixin {
  StoresDao(super.attachedDatabase);

  // ---------------------------------------------------------------------------
  // Toko
  // ---------------------------------------------------------------------------

  /// Semua toko: aktif dulu, lalu nama.
  Stream<List<StoreRow>> watchAll() =>
      (select(stores)..orderBy([
            (s) => OrderingTerm.desc(s.isActive),
            (s) => OrderingTerm.asc(s.name),
          ]))
          .watch();

  Future<StoreRow?> findById(int id) =>
      (select(stores)..where((s) => s.id.equals(id))).getSingleOrNull();

  /// JSON bentuk struk toko [id] (`null` = template bawaan).
  Future<String?> receiptTemplateOf(int id) async {
    final q = selectOnly(stores)
      ..addColumns([stores.receiptTemplate])
      ..where(stores.id.equals(id));
    return (await q.getSingleOrNull())?.read(stores.receiptTemplate);
  }

  Stream<String?> watchReceiptTemplate(int id) {
    final q = selectOnly(stores)
      ..addColumns([stores.receiptTemplate])
      ..where(stores.id.equals(id));
    return q.watchSingleOrNull().map((r) => r?.read(stores.receiptTemplate));
  }

  Future<void> setReceiptTemplate(int id, String? json) =>
      (update(stores)..where((s) => s.id.equals(id))).write(
        StoresCompanion(receiptTemplate: Value(json)),
      );

  Future<List<int>> allIds() => (selectOnly(
    stores,
  )..addColumns([stores.id])).map((r) => r.read(stores.id)!).get();

  Future<StoreRow?> findByName(String name) =>
      (select(stores)
            ..where((s) => s.name.lower().equals(name.trim().toLowerCase())))
          .getSingleOrNull();

  Future<int> insertStore(StoresCompanion row) => into(stores).insert(row);

  Future<void> updateStore(int id, StoresCompanion row) =>
      (update(stores)..where((s) => s.id.equals(id))).write(row);

  Future<int> deleteStore(int id) => transaction(() async {
    await (delete(storeProducts)..where((p) => p.storeId.equals(id))).go();
    return (delete(stores)..where((s) => s.id.equals(id))).go();
  });

  Future<int> countActive() async {
    final count = stores.id.count();
    final row =
        await (selectOnly(stores)
              ..addColumns([count])
              ..where(stores.isActive.equals(true)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Jumlah akun, faktur, dan riwayat stok milik toko [id].
  Future<({int users, int sales, int movements})> usage(int id) async {
    Future<int> count(String table) async {
      final row = await customSelect(
        'SELECT COUNT(*) AS n FROM $table WHERE store_id = ?',
        variables: [Variable.withInt(id)],
      ).getSingle();
      return row.read<int>('n');
    }

    return (
      users: await count('users'),
      sales: await count('sales'),
      movements: await count('stock_movements'),
    );
  }

  // ---------------------------------------------------------------------------
  // Stok & harga per toko
  // ---------------------------------------------------------------------------

  Future<StoreProductRow?> entry(int storeId, int productId) =>
      (select(storeProducts)..where(
            (p) => p.storeId.equals(storeId) & p.productId.equals(productId),
          ))
          .getSingleOrNull();

  /// Semua baris toko untuk satu barang (form barang admin).
  Future<List<StoreProductRow>> entriesOf(int productId) => (select(
    storeProducts,
  )..where((p) => p.productId.equals(productId))).get();

  /// Menambah [delta] ke stok toko (negatif = berkurang) dan mencatat
  /// riwayatnya. Baris toko dibuat jika belum ada. Dipanggil di dalam
  /// transaksi.
  Future<void> changeStock({
    required int storeId,
    required int productId,
    required double delta,
    required StockMovementType type,
    required int? userId,
    int? refId,
    String? note,
  }) async {
    await customInsert(
      'INSERT INTO store_products (uuid, store_id, product_id, stock) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT (store_id, product_id) DO UPDATE SET stock = stock + ?',
      variables: [
        Variable.withString(newUuid()),
        Variable.withInt(storeId),
        Variable.withInt(productId),
        Variable.withReal(delta),
        Variable.withReal(delta),
      ],
      updates: {storeProducts},
    );
    await attachedDatabase.sealsDao.resealStoreProduct(storeId, productId);
    await into(stockMovements).insert(
      StockMovementsCompanion.insert(
        productId: productId,
        storeId: Value(storeId),
        userId: Value(userId),
        type: type,
        qtyChange: delta,
        refId: Value(refId),
        note: Value(note),
      ),
    );
  }

  /// Mengatur harga khusus toko; `null` = kembali ke harga default.
  Future<void> setPrice({
    required int storeId,
    required int productId,
    required int? price,
  }) async {
    await customInsert(
      'INSERT INTO store_products (uuid, store_id, product_id, selling_price) '
      'VALUES (?, ?, ?, ?) '
      'ON CONFLICT (store_id, product_id) DO UPDATE SET selling_price = ?',
      variables: [
        Variable.withString(newUuid()),
        Variable.withInt(storeId),
        Variable.withInt(productId),
        Variable(price),
        Variable(price),
      ],
      updates: {storeProducts},
    );
    await attachedDatabase.sealsDao.resealStoreProduct(storeId, productId);
  }

  /// Riwayat stok barang di satu toko beserta nama user, terbaru dulu.
  Stream<List<(StockMovementRow, String?)>> watchMovements(
    int storeId,
    int productId, {
    int limit = 20,
  }) {
    final query =
        select(stockMovements).join([
            leftOuterJoin(users, users.id.equalsExp(stockMovements.userId)),
          ])
          ..where(
            stockMovements.storeId.equals(storeId) &
                stockMovements.productId.equals(productId),
          )
          ..orderBy([OrderingTerm.desc(stockMovements.id)])
          ..limit(limit);
    return query
        .map(
          (r) =>
              (r.readTable(stockMovements), r.readTableOrNull(users)?.fullName),
        )
        .watch();
  }
}
