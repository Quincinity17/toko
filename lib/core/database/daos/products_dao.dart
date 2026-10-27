import 'package:drift/drift.dart';

import '../../../features/products/domain/product.dart';
import '../../../features/products/domain/product_pricing.dart';
import '../../../features/products/domain/tag.dart';
import '../app_database.dart';
import '../tables/products.dart';
import '../tables/sales.dart';
import '../tables/stores.dart';
import '../tables/tags.dart';

part 'products_dao.g.dart';

/// Stok dan harga barang untuk satu toko, atau semua toko (`storeId` null:
/// stok dijumlah, harga default). Dihitung lewat subquery ke
/// `store_products`; [watchedTables] membuat stream ikut terbarui saat stok
/// atau harga toko berubah.
class _StoreCols {
  _StoreCols(
    this.storeId,
    TableInfo sp,
    $ProductsTable products, {
    required TableInfo productUnits,
    required TableInfo priceTiers,
    required TableInfo storeUnitPrices,
  }) : unitList = CustomExpression<String>(
         // Satuan lain: `id␞nama␞isi␞barcode␞harga toko␞harga default`
         // dipisah `␟`.
         "(SELECT group_concat(pu.id || char(30) || pu.name || char(30) || "
         "pu.factor || char(30) || COALESCE(pu.barcode, '') || char(30) || "
         '${storeId == null ? 'pu.selling_price' : 'COALESCE((SELECT sup.selling_price FROM store_unit_prices sup WHERE sup.product_unit_id = pu.id AND sup.store_id = $storeId), pu.selling_price)'}'
         ' || char(30) || pu.selling_price, char(31)) FROM product_units pu '
         'WHERE pu.product_id = products.id)',
         watchedTables: [productUnits, storeUnitPrices],
       ),
       // Harga grosir: `jumlah minimal␞harga`. Toko yang punya grosir
       // sendiri memakai miliknya saja; lainnya grosir semua toko.
       tierList = CustomExpression<String>(
         '(SELECT group_concat(pt.min_qty || char(30) || pt.price, char(31)) '
         'FROM price_tiers pt WHERE pt.product_id = products.id AND '
         '${storeId == null ? 'pt.store_id IS NULL' : 'pt.store_id IS (CASE WHEN EXISTS (SELECT 1 FROM price_tiers x WHERE x.product_id = products.id AND x.store_id = $storeId) THEN $storeId END)'})',
         watchedTables: [priceTiers],
       ),
       stock = CustomExpression<double>(
         storeId == null
             ? '(SELECT COALESCE(SUM(sp.stock), 0) FROM store_products sp '
                   'WHERE sp.product_id = products.id)'
             : 'COALESCE((SELECT sp.stock FROM store_products sp '
                   'WHERE sp.product_id = products.id '
                   'AND sp.store_id = $storeId), 0)',
         watchedTables: [sp],
       ),
       price = storeId == null
           ? products.sellingPrice
           : CustomExpression<int>(
               'COALESCE((SELECT sp.selling_price FROM store_products sp '
               'WHERE sp.product_id = products.id AND sp.store_id = $storeId), '
               'products.selling_price)',
               watchedTables: [sp],
             );

  final int? storeId;
  final Expression<double> stock;
  final Expression<int> price;
  final Expression<String> unitList;
  final Expression<String> tierList;
}

@DriftAccessor(
  tables: [
    Products,
    Units,
    SaleItems,
    StockMovements,
    StoreProducts,
    Tags,
    ProductTags,
    ProductUnits,
    PriceTiers,
    StoreUnitPrices,
  ],
)
class ProductsDao extends DatabaseAccessor<AppDatabase>
    with _$ProductsDaoMixin {
  ProductsDao(super.attachedDatabase);

  _StoreCols _cols(int? storeId) => _StoreCols(
    storeId,
    storeProducts,
    products,
    productUnits: productUnits,
    priceTiers: priceTiers,
    storeUnitPrices: storeUnitPrices,
  );

  /// Tag barang dalam satu teks: `id␞nama␞warna` dipisah `␟` (karakter
  /// kontrol yang tidak mungkin ada di nama tag).
  late final _tagList = CustomExpression<String>(
    '(SELECT group_concat(t.id || char(30) || t.name || char(30) || t.color, '
    'char(31)) FROM product_tags pt JOIN tags t ON t.id = pt.tag_id '
    'WHERE pt.product_id = products.id)',
    watchedTables: [productTags, tags],
  );

  JoinedSelectStatement<HasResultSet, dynamic> _joined(_StoreCols cols) {
    return select(products)
        .join([leftOuterJoin(units, units.id.equalsExp(products.unitId))])
      ..addColumns([
        cols.stock,
        cols.price,
        _tagList,
        cols.unitList,
        cols.tierList,
      ]);
  }

  static List<ProductUnit> _parseUnits(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final item in raw.split('\u001f'))
        if (item.split('\u001e') case [
          final id,
          final name,
          final factor,
          final barcode,
          final price,
          final defaultPrice,
        ])
          ProductUnit(
            id: int.parse(id),
            name: name,
            factor: double.parse(factor),
            barcode: barcode.isEmpty ? null : barcode,
            price: int.parse(price),
            defaultPrice: int.parse(defaultPrice),
          ),
    ]..sort((a, b) => a.factor.compareTo(b.factor));
  }

  static List<PriceTier> _parseTiers(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final item in raw.split('\u001f'))
        if (item.split('\u001e') case [final min, final price])
          PriceTier(minQty: double.parse(min), price: int.parse(price)),
    ]..sort((a, b) => a.minQty.compareTo(b.minQty));
  }

  static List<Tag> _parseTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final out = <Tag>[
      for (final item in raw.split('\u001f'))
        if (item.split('\u001e') case [final id, final name, final color])
          Tag(id: int.parse(id), name: name, color: TagColor.of(color)),
    ];
    return out
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Product _read(TypedResult r, _StoreCols cols) {
    final p = r.readTable(products);
    return Product(
      id: p.id,
      code: p.code,
      barcode: p.barcode,
      name: p.name,
      unitId: p.unitId,
      unitName: r.readTableOrNull(units)?.name,
      purchasePrice: p.purchasePrice,
      sellingPrice: r.read(cols.price) ?? p.sellingPrice,
      defaultSellingPrice: p.sellingPrice,
      stock: r.read(cols.stock) ?? 0,
      minStock: p.minStock,
      isActive: p.isActive,
      tags: _parseTags(r.read(_tagList)),
      units: _parseUnits(r.read(cols.unitList)),
      tiers: _parseTiers(r.read(cols.tierList)),
    );
  }

  // ---------------------------------------------------------------------------
  // Kasir
  // ---------------------------------------------------------------------------

  /// Cocok persis dengan kode (tanpa peduli huruf besar/kecil) atau barcode.
  /// Dipakai untuk scan barcode dan ketik kode di kasir.
  Future<Product?> findActiveByCodeOrBarcode(
    String value, {
    required int? storeId,
  }) async {
    final v = value.trim();
    final cols = _cols(storeId);
    final query = _joined(cols)
      ..where(
        products.isActive.equals(true) &
            (products.code.lower().equals(v.toLowerCase()) |
                products.barcode.equals(v)),
      )
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _read(row, cols);
  }

  /// Barang aktif yang punya satuan lain dengan barcode kemasan [value]:
  /// `(barang, id satuan)`.
  Future<(Product, int)?> findActiveByUnitBarcode(
    String value, {
    required int? storeId,
  }) async {
    final unit = await (select(
      productUnits,
    )..where((u) => u.barcode.equals(value.trim()))).getSingleOrNull();
    if (unit == null) return null;
    final product = await findById(unit.productId, storeId: storeId);
    if (product == null || !product.isActive) return null;
    return (product, unit.id);
  }

  /// Satuan lain mana pun dengan barcode kemasan [barcode].
  Future<ProductUnitRow?> findUnitByBarcode(String barcode) => (select(
    productUnits,
  )..where((u) => u.barcode.equals(barcode.trim()))).getSingleOrNull();

  /// Mengganti satuan lain & harga grosir barang [productId]. Satuan yang
  /// sudah ada (id sama) diubah di tempat supaya id-nya tetap (keranjang &
  /// transaksi tertahan menyimpan id satuan).
  Future<void> setPricing(
    int productId, {
    List<ProductUnit>? unitList,
    List<PriceTier>? tierList,
  }) async {
    if (unitList != null) {
      final keep = {for (final u in unitList) ?u.id};
      await (delete(
        productUnits,
      )..where((u) => u.productId.equals(productId) & u.id.isNotIn(keep))).go();
      // Lepas barcode dulu supaya tukar barcode antar satuan tidak bentrok.
      await (update(productUnits)..where((u) => u.productId.equals(productId)))
          .write(const ProductUnitsCompanion(barcode: Value(null)));
      for (final u in unitList) {
        final data = ProductUnitsCompanion(
          productId: Value(productId),
          name: Value(PricingRules.unitName(u.name)),
          factor: Value(u.factor),
          barcode: Value(
            (u.barcode?.trim().isEmpty ?? true) ? null : u.barcode!.trim(),
          ),
          sellingPrice: Value(u.price),
        );
        final id = u.id;
        if (id == null) {
          await into(productUnits).insert(data);
        } else {
          await (update(
            productUnits,
          )..where((t) => t.id.equals(id))).write(data);
        }
      }
    }
    if (tierList != null) {
      await (delete(
        priceTiers,
      )..where((t) => t.productId.equals(productId) & t.storeId.isNull())).go();
      for (final t in tierList) {
        await into(priceTiers).insert(
          PriceTiersCompanion.insert(
            productId: productId,
            minQty: t.minQty,
            price: t.price,
          ),
        );
      }
    }
    await attachedDatabase.sealsDao.resealPricing(productId);
  }

  /// Harga khusus toko satuan lain barang [productId]:
  /// `(toko, nama satuan, harga)`.
  Future<List<(int, String, int)>> storeUnitPricesOf(int productId) async {
    final rows = await customSelect(
      'SELECT sup.store_id, pu.name, sup.selling_price FROM store_unit_prices '
      'sup JOIN product_units pu ON pu.id = sup.product_unit_id '
      'WHERE pu.product_id = ?',
      variables: [Variable.withInt(productId)],
      readsFrom: {storeUnitPrices, productUnits},
    ).get();
    return [
      for (final r in rows)
        (
          r.read<int>('store_id'),
          r.read<String>('name'),
          r.read<int>('selling_price'),
        ),
    ];
  }

  /// Grosir khusus toko barang [productId], urut jumlah minimal.
  Future<List<PriceTierRow>> storeTiersOf(int productId) =>
      (select(priceTiers)
            ..where(
              (t) => t.productId.equals(productId) & t.storeId.isNotNull(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.minQty)]))
          .get();

  /// Harga satuan [unitId] di toko [storeId]; `null` = harga satuan itu.
  Future<void> setStoreUnitPrice(int storeId, int unitId, int? price) async {
    if (price == null) {
      await (delete(storeUnitPrices)..where(
            (t) => t.storeId.equals(storeId) & t.productUnitId.equals(unitId),
          ))
          .go();
      return;
    }
    await into(storeUnitPrices).insert(
      StoreUnitPricesCompanion.insert(
        storeId: storeId,
        productUnitId: unitId,
        sellingPrice: price,
      ),
      onConflict: DoUpdate(
        (_) => StoreUnitPricesCompanion(sellingPrice: Value(price)),
        target: [storeUnitPrices.storeId, storeUnitPrices.productUnitId],
      ),
    );
  }

  /// Mengganti grosir khusus toko [storeId]; kosong = ikut grosir semua
  /// toko.
  Future<void> setStoreTiers(
    int productId,
    int storeId,
    List<PriceTier> tiers,
  ) async {
    await (delete(priceTiers)..where(
          (t) => t.productId.equals(productId) & t.storeId.equals(storeId),
        ))
        .go();
    for (final t in tiers) {
      await into(priceTiers).insert(
        PriceTiersCompanion.insert(
          productId: productId,
          minQty: t.minQty,
          price: t.price,
          storeId: Value(storeId),
        ),
      );
    }
  }

  /// Pencarian per kata: setiap kata harus ada di nama, atau menjadi awalan
  /// kode/barcode. Urutan kata bebas ("goreng indomie" = "indomie goreng").
  Future<List<Product>> searchActive(
    String text, {
    required int? storeId,
    int limit = 50,
  }) {
    final cols = _cols(storeId);
    final query = _joined(cols)
      ..where(products.isActive.equals(true) & _textFilter(text))
      ..orderBy([OrderingTerm.asc(products.name)])
      ..limit(limit);
    return query.map((r) => _read(r, cols)).get();
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

  /// Nama dan kode semua barang aktif, bahan pengecekan nama mirip.
  Future<List<({String name, String code})>> activeNameCodes() {
    final query = selectOnly(products)
      ..addColumns([products.name, products.code])
      ..where(products.isActive.equals(true));
    return query
        .map(
          (r) => (name: r.read(products.name)!, code: r.read(products.code)!),
        )
        .get();
  }

  /// Kode semua barang (aktif maupun tidak), terbaru dulu; bahan nomor
  /// barcode otomatis.
  Future<List<String>> codesNewestFirst() {
    final query = selectOnly(products)
      ..addColumns([products.code])
      ..orderBy([OrderingTerm.desc(products.id)]);
    return query.map((r) => r.read(products.code)!).get();
  }

  /// Kode barang yang punya kategori (tag) bernama [tagName] (tanpa peduli
  /// huruf besar), terbaru dulu; seri barcode otomatis per kategori.
  Future<List<String>> codesInTag(String tagName) async {
    final rows = await customSelect(
      'SELECT p.code FROM products p '
      'JOIN product_tags pt ON pt.product_id = p.id '
      'JOIN tags t ON t.id = pt.tag_id '
      'WHERE lower(t.name) = lower(?) ORDER BY p.id DESC',
      variables: [Variable.withString(tagName.trim())],
      readsFrom: {products, productTags, tags},
    ).get();
    return [for (final r in rows) r.read<String>('code')];
  }

  /// Semua barcode kemasan (satuan lain); ikut dianggap terpakai.
  Future<List<String>> unitBarcodes() async {
    final query = selectOnly(productUnits)
      ..addColumns([productUnits.barcode])
      ..where(productUnits.barcode.isNotNull());
    return query.map((r) => r.read(productUnits.barcode)!).get();
  }

  /// Barang berdasarkan id, mengikuti urutan [ids].
  Future<List<Product>> byIds(List<int> ids, {required int? storeId}) async {
    if (ids.isEmpty) return const [];
    final cols = _cols(storeId);
    final rows = await (_joined(
      cols,
    )..where(products.id.isIn(ids))).map((r) => _read(r, cols)).get();
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

  Expression<bool> _filter(ProductFilter f, _StoreCols cols) {
    Expression<bool> e = _textFilter(f.text);
    e = switch (f.status) {
      ProductStatusFilter.active => e & products.isActive.equals(true),
      ProductStatusFilter.inactive => e & products.isActive.equals(false),
      ProductStatusFilter.all => e,
    };
    if (f.tagId != null) {
      e =
          e &
          CustomExpression<bool>(
            'EXISTS (SELECT 1 FROM product_tags pt WHERE '
            'pt.product_id = products.id AND pt.tag_id = ${f.tagId})',
            watchedTables: [productTags],
          );
    }
    if (f.lowStockOnly) {
      e = e & cols.stock.isSmallerOrEqual(products.minStock);
    }
    return e;
  }

  List<OrderingTerm> _order(ProductSort sort, _StoreCols cols) =>
      switch (sort) {
        ProductSort.name => [OrderingTerm.asc(products.name)],
        ProductSort.code => [OrderingTerm.asc(products.code)],
        ProductSort.stockLow => [
          OrderingTerm.asc(cols.stock),
          OrderingTerm.asc(products.name),
        ],
        ProductSort.priceHigh => [
          OrderingTerm.desc(cols.price),
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
    final cols = _cols(f.storeId);
    final query = _joined(cols)
      ..where(_filter(f, cols))
      ..orderBy(_order(f.sort, cols))
      ..limit(limit, offset: offset);
    return query.map((r) => _read(r, cols)).watch();
  }

  Stream<int> watchCount(ProductFilter f) {
    final cols = _cols(f.storeId);
    final count = products.id.count();
    final query = selectOnly(products)
      ..addColumns([count])
      ..where(_filter(f, cols));
    return query.map((r) => r.read(count) ?? 0).watchSingle();
  }

  /// Semua barang sesuai filter, untuk export.
  Future<List<Product>> allMatching(ProductFilter f) {
    final cols = _cols(f.storeId);
    return (_joined(cols)
          ..where(_filter(f, cols))
          ..orderBy(_order(f.sort, cols)))
        .map((r) => _read(r, cols))
        .get();
  }

  Future<Product?> findById(int id, {int? storeId}) async {
    final cols = _cols(storeId);
    final row = await (_joined(
      cols,
    )..where(products.id.equals(id))).getSingleOrNull();
    return row == null ? null : _read(row, cols);
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

  // Setiap penulisan menyegel ulang baris (lihat SealsDao).
  Future<int> insertProduct(ProductsCompanion p) async {
    final id = await into(products).insert(p);
    await attachedDatabase.sealsDao.resealProduct(id);
    return id;
  }

  Future<void> updateProduct(int id, ProductsCompanion p) async {
    await (update(products)..where((t) => t.id.equals(id))).write(p);
    await attachedDatabase.sealsDao.resealProduct(id);
  }

  /// Menghapus barang beserta riwayat stok dan data per tokonya. Hanya untuk
  /// barang yang belum pernah terjual (dicek pemanggil).
  Future<void> deleteProduct(int id) async {
    await (delete(stockMovements)..where((m) => m.productId.equals(id))).go();
    await (delete(storeProducts)..where((p) => p.productId.equals(id))).go();
    await (delete(productTags)..where((p) => p.productId.equals(id))).go();
    await (delete(productUnits)..where((p) => p.productId.equals(id))).go();
    await (delete(priceTiers)..where((p) => p.productId.equals(id))).go();
    await (delete(products)..where((p) => p.id.equals(id))).go();
  }

  // ---------------------------------------------------------------------------
  // Satuan (kategori = tag, lihat TagsDao)
  // ---------------------------------------------------------------------------

  Stream<List<UnitRow>> watchUnits() =>
      (select(units)..orderBy([(u) => OrderingTerm.asc(u.name)])).watch();

  /// Id satuan dengan nama itu; dibuat jika belum ada. Nama satuan disimpan huruf besar
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
