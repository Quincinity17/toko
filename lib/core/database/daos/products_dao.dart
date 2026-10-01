import 'package:drift/drift.dart';

import '../../../features/products/domain/product.dart';
import '../app_database.dart';
import '../tables/products.dart';

part 'products_dao.g.dart';

@DriftAccessor(tables: [Products, Categories, Units])
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
      categoryName: r.readTableOrNull(categories)?.name,
      unitName: r.readTableOrNull(units)?.name,
      purchasePrice: p.purchasePrice,
      sellingPrice: p.sellingPrice,
      stock: p.stock,
      minStock: p.minStock,
    );
  }

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
    final words = text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty);
    final query = _joined()
      ..where(products.isActive.equals(true))
      ..orderBy([OrderingTerm.asc(products.name)])
      ..limit(limit);
    for (final w in words) {
      final e = _escapeLike(w);
      query.where(
        products.name.lower().like('%$e%', escapeChar: r'\') |
            products.code.lower().like('$e%', escapeChar: r'\') |
            products.barcode.like('$e%', escapeChar: r'\'),
      );
    }
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

  /// `%` dan `_` yang diketik user diperlakukan sebagai huruf biasa.
  static String _escapeLike(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
