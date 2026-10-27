import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../products/domain/product.dart';
import '../../products/domain/product_pricing.dart';
import '../domain/label_layout.dart';

/// Daftar label yang akan dicetak (halaman Cetak Label). Bisa diisi dari
/// halaman lain (Produk sesuai filter, Barang Masuk) lalu dibuka.
class LabelQueue extends Notifier<List<LabelItem>> {
  @override
  List<LabelItem> build() => const [];

  /// Menambah [item]; barang & satuan yang sama digabung jumlahnya.
  void add(LabelItem item) {
    final i = state.indexWhere((x) => x.sameAs(item));
    state = i == -1
        ? [...state, item]
        : [
            for (final (j, x) in state.indexed)
              j == i ? x.copyWith(copies: x.copies + item.copies) : x,
          ];
  }

  void addProduct(Product p, {ProductUnit? unit, int copies = 1}) =>
      add(LabelItem.of(p, unit: unit, copies: copies));

  void setCopies(int index, int copies) => state = [
    for (final (j, x) in state.indexed)
      if (j != index) x else if (copies > 0) x.copyWith(copies: copies),
  ];

  void removeAt(int index) => state = [...state]..removeAt(index);

  void clear() => state = const [];
}

final labelQueueProvider = NotifierProvider<LabelQueue, List<LabelItem>>(
  LabelQueue.new,
);
