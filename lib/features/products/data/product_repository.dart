import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/fuzzy_match.dart';
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

  /// Saran barang dengan nama yang mendekati [text] (salah ketik dll.),
  /// dipakai saat [search] tidak menemukan apa pun.
  Future<List<Product>> suggest(String text, {int limit = 8}) async {
    if (text.trim().length < 3) return const [];
    final names = await _db.productsDao.activeNames();
    final ids = FuzzyMatch.rank(text, names, (n) => n.$2, limit: limit);
    return _db.productsDao.byIds([for (final (id, _) in ids) id]);
  }
}

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(ref.watch(appDatabaseProvider)),
);
