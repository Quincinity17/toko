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

  /// Pencarian nama (mengandung kata), kode, atau barcode (diawali kata).
  Future<List<Product>> searchActive(String text, {int limit = 50}) {
    final q = text.trim().toLowerCase();
    final query = _joined()
      ..where(products.isActive.equals(true))
      ..orderBy([OrderingTerm.asc(products.name)])
      ..limit(limit);
    if (q.isNotEmpty) {
      query.where(
        products.name.lower().like('%$q%') |
            products.code.lower().like('$q%') |
            products.barcode.like('$q%'),
      );
    }
    return query.map(_read).get();
  }
}
