import 'package:flutter/foundation.dart';

import '../../products/domain/product.dart';

enum DiscountType { percent, amount }

/// Satu baris keranjang. Total baris = qty × harga − potongan % baris,
/// dibulatkan ke Rupiah terdekat.
@immutable
class CartLine {
  const CartLine({
    required this.product,
    required this.qty,
    this.discountPercent = 0,
  });

  final Product product;
  final double qty;
  final double discountPercent;

  int get price => product.sellingPrice;

  int get total => (qty * price * (100 - discountPercent) / 100).round();

  /// Stok di database tidak cukup untuk qty ini (penjualan tetap diizinkan).
  bool get exceedsStock => qty > product.stock;

  CartLine copyWith({double? qty, double? discountPercent}) => CartLine(
    product: product,
    qty: qty ?? this.qty,
    discountPercent: discountPercent ?? this.discountPercent,
  );
}

/// Keranjang belanja yang sedang diproses kasir. Immutable: setiap perubahan
/// menghasilkan objek baru.
@immutable
class Cart {
  const Cart({
    this.lines = const [],
    this.discountType = DiscountType.percent,
    this.discountValue = 0,
  });

  final List<CartLine> lines;
  final DiscountType discountType;

  /// Persen (0–100) atau nominal Rupiah, sesuai [discountType].
  final double discountValue;

  bool get isEmpty => lines.isEmpty;

  /// Jumlah semua qty (mis. 3 indomie + 0,5 kg telur = 3,5).
  double get totalQty => lines.fold(0, (s, l) => s + l.qty);

  int get subtotal => lines.fold(0, (s, l) => s + l.total);

  /// Potongan per transaksi dalam Rupiah, tidak pernah melebihi subtotal.
  int get discount {
    final raw = switch (discountType) {
      DiscountType.percent => (subtotal * discountValue / 100).round(),
      DiscountType.amount => discountValue.round(),
    };
    return raw.clamp(0, subtotal);
  }

  int get total => subtotal - discount;

  Cart copyWith({
    List<CartLine>? lines,
    DiscountType? discountType,
    double? discountValue,
  }) => Cart(
    lines: lines ?? this.lines,
    discountType: discountType ?? this.discountType,
    discountValue: discountValue ?? this.discountValue,
  );

  /// Menambah barang. Jika barang yang sama sudah ada, qty-nya dijumlahkan.
  Cart add(Product product, {double qty = 1}) {
    final i = lines.indexWhere((l) => l.product.id == product.id);
    if (i == -1) {
      return copyWith(
        lines: [
          ...lines,
          CartLine(product: product, qty: qty),
        ],
      );
    }
    return _replace(i, lines[i].copyWith(qty: lines[i].qty + qty));
  }

  /// Qty ≤ 0 menghapus baris.
  Cart setQty(int index, double qty) {
    if (qty <= 0) return removeAt(index);
    return _replace(index, lines[index].copyWith(qty: qty));
  }

  Cart setLineDiscount(int index, double percent) => _replace(
    index,
    lines[index].copyWith(discountPercent: percent.clamp(0, 100)),
  );

  Cart removeAt(int index) => copyWith(lines: [...lines]..removeAt(index));

  Cart setDiscount(DiscountType type, double value) => copyWith(
    discountType: type,
    discountValue: switch (type) {
      DiscountType.percent => value.clamp(0, 100),
      DiscountType.amount => value < 0 ? 0 : value,
    },
  );

  Cart _replace(int index, CartLine line) =>
      copyWith(lines: [...lines]..[index] = line);
}
