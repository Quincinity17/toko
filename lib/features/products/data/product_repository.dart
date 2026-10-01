import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/product.dart';

class ProductRepository {
  ProductRepository(this._db);

  final AppDatabase _db;

  /// Untuk scan barcode / ketik kode di kasir: harus cocok persis.
  Future<Product?> findByCodeOrBarcode(String value) {
    if (value.trim().isEmpty) return Future.value(null);
    return _db.productsDao.findActiveByCodeOrBarcode(value);
  }

  Future<List<Product>> search(String text, {int limit = 50}) =>
      _db.productsDao.searchActive(text, limit: limit);
}

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(ref.watch(appDatabaseProvider)),
);
