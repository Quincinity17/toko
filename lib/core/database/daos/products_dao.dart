import 'package:drift/drift.dart';

import '../../../features/products/domain/product.dart';
import '../app_database.dart';
import '../tables/products.dart';
import '../tables/sales.dart';

part 'products_dao.g.dart';

@DriftAccessor(tables: [Products, Categories, Units, SaleItems, StockMovements])
class ProductsDao extends DatabaseAccessor<AppDatabase>
    with _$ProductsDaoMixin {
  ProductsDao(super.attachedDatabase);

  JoinedSelectStatement<HasResultSet, dynamic> _joined() {
    return select(products).join([
      leftOuterJoin(categories, categories.id.equalsExp(products.categoryId)),
      leftOuterJoin(units, units.id.equalsExp(products.unitId)),
    ]);
  }

  Product _read(TypedResult r) {
    final p = r.readTable(products);
    return Product(
      id: p.id,
      code: p.code,
      barcode: p.barcode,
      name: p.name,
      categoryId: p.categoryId,
      categoryName: r.readTableOrNull(categories)?.name,
      unitId: p.unitId,
      unitName: r.readTableOrNull(units)?.name,
      purchasePrice: p.purchasePrice,
      sellingPrice: p.sellingPrice,
      stock: p.stock,
      minStock: p.minStock,
      isActive: p.isActive,
    );
  }

  // ---------------------------------------------------------------------------
  // Kasir
  // ---------------------------------------------------------------------------

  /// Cocok persis dengan kode (tanpa peduli huruf besar/kecil) atau barcode.
  /// Dipakai untuk scan barcode dan ketik kode di kasir.
  Future<Product?> findActiveByCodeOrBarcode(String value) async {
    final v = value.trim();
    final query = _joined()
      ..where(
        products.isActive.equals(true) &
            (products.code.lower().equals(v.toLowerCase()) |
                products.barcode.equals(v)),
      )
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _read(row);
  }

  /// Pencarian per kata: setiap kata harus ada di nama, atau menjadi awalan
  /// kode/barcode. Urutan kata bebas ("goreng indomie" = "indomie goreng").
  Future<List<Product>> searchActive(String text, {int limit = 50}) {
    final query = _joined()
      ..where(products.isActive.equals(true) & _textFilter(text))
      ..orderBy([OrderingTerm.asc(products.name)])
      ..limit(limit);
    return query.map(_read).get();
  }

  /// Id dan nama semua barang aktif, bahan untuk saran nama yang mendekati.
  Future<List<(int, String)>> activeNames() {
    final query = selectOnly(products)
      ..addColumns([products.id, products.name])
      ..where(products.isActive.equals(true));
    return query
        .map((r) => (r.read(products.id)!, r.read(products.name)!))
        .get();
  }

  /// Barang berdasarkan id, mengikuti urutan [ids].
  Future<List<Product>> byIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await (_joined()..where(products.id.isIn(ids)))
        .map(_read)
        .get();
    final byId = {for (final p in rows) p.id: p};
    return [for (final id in ids) ?byId[id]];
  }

  // ---------------------------------------------------------------------------
  // Halaman Produk (admin)
  // ---------------------------------------------------------------------------

  Expression<bool> _textFilter(String text) {
    final words = text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    Expression<bool> all = const Constant(true);
    for (final w in words) {
      final e = _escapeLike(w);
      all =
          all &
          (products.name.lower().like('%$e%', escapeChar: r'\') |
              products.code.lower().like('$e%', escapeChar: r'\') |
              products.barcode.like('$e%', escapeChar: r'\'));
    }
    return all;
  }

  Expression<bool> _filter(ProductFilter f) {
    Expression<bool> e = _textFilter(f.text);
    e = switch (f.status) {
      ProductStatusFilter.active => e & products.isActive.equals(true),
      ProductStatusFilter.inactive => e & products.isActive.equals(false),
      ProductStatusFilter.all => e,
    };
    if (f.categoryId != null) e = e & products.categoryId.equals(f.categoryId!);
    if (f.lowStockOnly) {
      e = e & products.stock.isSmallerOrEqual(products.minStock);
    }
    return e;
  }

  List<OrderingTerm> _order(ProductSort sort) => switch (sort) {
    ProductSort.name => [OrderingTerm.asc(products.name)],
    ProductSort.code => [OrderingTerm.asc(products.code)],
    ProductSort.stockLow => [
      OrderingTerm.asc(products.stock),
      OrderingTerm.asc(products.name),
    ],
    ProductSort.priceHigh => [
      OrderingTerm.desc(products.sellingPrice),
      OrderingTerm.asc(products.name),
    ],
    ProductSort.updated => [
      OrderingTerm.desc(products.updatedAt),
      OrderingTerm.desc(products.id),
    ],
  };

  Stream<List<Product>> watchPage(
    ProductFilter f, {
    required int offset,
    required int limit,
  }) {
    final query = _joined()
      ..where(_filter(f))
      ..orderBy(_order(f.sort))
      ..limit(limit, offset: offset);
    return query.map(_read).watch();
  }

  Stream<int> watchCount(ProductFilter f) {
    final count = products.id.count();
    final query = selectOnly(products)
      ..addColumns([count])
      ..where(_filter(f));
    return query.map((r) => r.read(count) ?? 0).watchSingle();
  }

  /// Semua barang sesuai filter, untuk export.
  Future<List<Product>> allMatching(ProductFilter f) =>
      (_joined()
            ..where(_filter(f))
            ..orderBy(_order(f.sort)))
          .map(_read)
          .get();

  Future<Product?> findById(int id) async {
    final row = await (_joined()..where(products.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _read(row);
  }

  /// Barang (aktif maupun tidak) dengan kode sama, tanpa peduli huruf besar.
  Future<ProductRow?> findByCode(String code) =>
      (select(products)
            ..where((p) => p.code.lower().equals(code.trim().toLowerCase())))
          .getSingleOrNull();

  Future<ProductRow?> findByBarcode(String barcode) => (select(
    products,
  )..where((p) => p.barcode.equals(barcode.trim()))).getSingleOrNull();

  Future<int> countSaleItems(int productId) async {
    final count = saleItems.id.count();
    final row =
        await (selectOnly(saleItems)
              ..addColumns([count])
              ..where(saleItems.productId.equals(productId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> insertProduct(ProductsCompanion p) => into(products).insert(p);

  Future<void> updateProduct(int id, ProductsCompanion p) =>
      (update(products)..where((t) => t.id.equals(id))).write(p);

  /// Menghapus barang beserta riwayat stoknya. Hanya untuk barang yang belum
  /// pernah terjual (dicek pemanggil).
  Future<void> deleteProduct(int id) async {
    await (delete(stockMovements)..where((m) => m.productId.equals(id))).go();
    await (delete(products)..where((p) => p.id.equals(id))).go();
  }

  Future<void> addStockMovement({
    required int productId,
    required StockMovementType type,
    required double qtyChange,
    String? note,
  }) => into(stockMovements).insert(
    StockMovementsCompanion.insert(
      productId: productId,
      type: type,
      qtyChange: qtyChange,
      note: Value(note),
    ),
  );

  // ---------------------------------------------------------------------------
  // Kategori & satuan
  // ---------------------------------------------------------------------------

  Stream<List<CategoryRow>> watchCategories() =>
      (select(categories)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  Stream<List<UnitRow>> watchUnits() =>
      (select(units)..orderBy([(u) => OrderingTerm.asc(u.name)])).watch();

  /// Id kategori dengan nama itu (tanpa peduli huruf besar); dibuat jika
  /// belum ada. `null` jika [name] kosong.
  Future<int?> categoryIdFor(String? name) async {
    final n = name?.trim() ?? '';
    if (n.isEmpty) return null;
    final existing = await (select(
      categories,
    )..where((c) => c.name.lower().equals(n.toLowerCase()))).getSingleOrNull();
    return existing?.id ??
        await into(categories).insert(CategoriesCompanion.insert(name: n));
  }

  /// Seperti [categoryIdFor], untuk satuan. Nama satuan disimpan huruf besar
  /// (PCS, KG, BTL) agar seragam.
  Future<int?> unitIdFor(String? name) async {
    final n = name?.trim().toUpperCase() ?? '';
    if (n.isEmpty) return null;
    final existing = await (select(
      units,
    )..where((u) => u.name.upper().equals(n))).getSingleOrNull();
    return existing?.id ??
        await into(units).insert(UnitsCompanion.insert(name: n));
  }

  /// `%` dan `_` yang diketik user diperlakukan sebagai huruf biasa.
  static String _escapeLike(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
