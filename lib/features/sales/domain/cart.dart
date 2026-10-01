import 'package:flutter/foundation.dart';

import '../../products/domain/product.dart';
import '../../vouchers/domain/voucher.dart';

/// Satu baris keranjang. Total baris = qty × harga, dibulatkan ke Rupiah.
@immutable
class CartLine {
  const CartLine({required this.product, required this.qty});

  final Product product;
  final double qty;

  int get price => product.sellingPrice;

  int get total => (qty * price).round();

  /// Stok di database tidak cukup untuk qty ini (penjualan tetap diizinkan).
  bool get exceedsStock => qty > product.stock;

  CartLine copyWith({double? qty}) =>
      CartLine(product: product, qty: qty ?? this.qty);
}

/// Keranjang belanja yang sedang diproses kasir. Immutable: setiap perubahan
/// menghasilkan objek baru. Satu-satunya potongan adalah [voucher].
@immutable
class Cart {
  const Cart({this.lines = const [], this.voucher});

  final List<CartLine> lines;

  /// Voucher yang sudah lolos pemeriksaan saat dipasang. Status/tanggal/kuota
  /// diperiksa ulang saat checkout; di sini hanya minimal belanja.
  final Voucher? voucher;

  bool get isEmpty => lines.isEmpty;

  /// Jumlah semua qty (mis. 3 indomie + 0,5 kg telur = 3,5).
  double get totalQty => lines.fold(0, (s, l) => s + l.qty);

  int get subtotal => lines.fold(0, (s, l) => s + l.total);

  /// Kekurangan belanja agar voucher berlaku (0 = sudah memenuhi).
  int get voucherShortfall {
    final v = voucher;
    if (v == null || subtotal >= v.minPurchase) return 0;
    return v.minPurchase - subtotal;
  }

  int get discount {
    final v = voucher;
    if (v == null || voucherShortfall > 0) return 0;
    return v.discountFor(subtotal);
  }

  int get total => subtotal - discount;

  /// Menambah barang. Jika barang yang sama sudah ada, qty-nya dijumlahkan.
  Cart add(Product product, {double qty = 1}) {
    final i = lines.indexWhere((l) => l.product.id == product.id);
    if (i == -1) {
      return Cart(
        lines: [
          ...lines,
          CartLine(product: product, qty: qty),
        ],
        voucher: voucher,
      );
    }
    return _replace(i, lines[i].copyWith(qty: lines[i].qty + qty));
  }

  /// Qty ≤ 0 menghapus baris.
  Cart setQty(int index, double qty) {
    if (qty <= 0) return removeAt(index);
    return _replace(index, lines[index].copyWith(qty: qty));
  }

  Cart removeAt(int index) =>
      Cart(lines: [...lines]..removeAt(index), voucher: voucher);

  Cart withVoucher(Voucher? voucher) => Cart(lines: lines, voucher: voucher);

  Cart _replace(int index, CartLine line) =>
      Cart(lines: [...lines]..[index] = line, voucher: voucher);
}
