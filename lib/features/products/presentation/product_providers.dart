import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/product_repository.dart';
import '../../stores/presentation/store_scope.dart';
import '../domain/product.dart';

const productPageSize = 50;

/// Satu halaman daftar barang untuk (filter, nomor halaman).
final productPageProvider = StreamProvider.autoDispose
    .family<List<Product>, (ProductFilter, int)>(
      (ref, key) => ref
          .watch(productRepositoryProvider)
          .watchPage(key.$1, page: key.$2, pageSize: productPageSize),
    );

final productCountProvider = StreamProvider.autoDispose
    .family<int, ProductFilter>(
      (ref, filter) => ref.watch(productRepositoryProvider).watchCount(filter),
    );

final unitNamesProvider = StreamProvider.autoDispose<List<String>>(
  (ref) => ref.watch(productRepositoryProvider).watchUnitNames(),
);

/// Saran nama mirip saat pencarian di halaman Produk kosong.
final productSuggestionsProvider = FutureProvider.autoDispose
    .family<List<Product>, String>(
      (ref, text) => ref
          .watch(productRepositoryProvider)
          .suggest(text, storeId: ref.watch(storeScopeProvider)),
    );
