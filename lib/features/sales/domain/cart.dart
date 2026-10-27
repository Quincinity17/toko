import 'package:flutter/foundation.dart';

import '../../products/domain/product.dart';
import '../../products/domain/product_pricing.dart';
import '../../vouchers/domain/voucher.dart';

/// Satu baris keranjang. Total baris = qty × harga, dibulatkan ke Rupiah.
///
/// [unit] = satuan lain (mis. DUS); `null` = satuan dasar barang. Harga
/// satuan dasar turun ke harga grosir bila jumlah barang itu di seluruh
/// keranjang ([groupBaseQty], semua satuan) mencapai jumlah minimalnya:
/// 1 DUS (24) + 5 PCS = 29 PCS.
@immutable
class CartLine {
  const CartLine({
    required this.product,
    required this.qty,
    this.unit,
    this.groupBaseQty,
  });

  final Product product;
  final double qty;
  final ProductUnit? unit;

  /// Jumlah satuan dasar barang ini di seluruh keranjang (diisi [Cart]);
  /// `null` = baris ini saja.
  final double? groupBaseQty;

  /// Jumlah penentu harga grosir & stok.
  double get _groupQty => groupBaseQty ?? baseQty;

  /// Isi satu satuan baris ini dalam satuan dasar.
  double get factor => unit?.factor ?? 1;

  /// Jumlah dalam satuan dasar (yang mengurangi stok).
  double get baseQty => qty * factor;

  String? get unitName => unit?.name ?? product.unitName;

  /// Harga normal satuan baris ini (tanpa grosir).
  int get normalPrice => unit?.price ?? product.sellingPrice;

  /// Harga grosir yang sedang berlaku (hanya satuan dasar, dan hanya bila
  /// lebih murah dari harga toko).
  PriceTier? get tier {
    if (unit != null) return null;
    final t = PricingRules.tierFor(product.tiers, _groupQty);
    return t != null && t.price < normalPrice ? t : null;
  }

  int get price => tier?.price ?? normalPrice;

  /// Harga grosir berikutnya yang belum tercapai (petunjuk untuk kasir).
  PriceTier? get nextTier {
    if (unit != null) return null;
    PriceTier? next;
    for (final t in product.tiers) {
      if (t.minQty > _groupQty + 1e-9 &&
          t.price < price &&
          (next == null || t.minQty < next.minQty)) {
        next = t;
      }
    }
    return next;
  }

  int get total => (qty * price).round();

  /// Harga beli per satuan baris ini (snapshot di faktur).
  int get purchasePrice => (product.purchasePrice * factor).round();

  /// Stok di database tidak cukup untuk qty ini (penjualan tetap diizinkan).
  bool get exceedsStock => _groupQty > product.stock;

  /// Baris yang sama = barang & satuan sama.
  bool sameItem(Product p, ProductUnit? u) =>
      product.id == p.id && unit?.id == u?.id;

  CartLine copyWith({
    double? qty,
    ProductUnit? Function()? unit,
    double? Function()? groupBaseQty,
  }) => CartLine(
    product: product,
    qty: qty ?? this.qty,
    unit: unit != null ? unit() : this.unit,
    groupBaseQty: groupBaseQty != null ? groupBaseQty() : this.groupBaseQty,
  );
}

/// Keranjang belanja yang sedang diproses kasir. Immutable: setiap perubahan
/// menghasilkan objek baru. Satu-satunya potongan adalah [voucher].
@immutable
class Cart {
  const Cart({this.lines = const [], this.voucher});

  final List<CartLine> lines;

  /// Voucher yang sudah lolos pemeriksaan saat dipasang. Status/tanggal/toko
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

  /// Menambah barang (dalam satuan [unit], `null` = satuan dasar). Jika
  /// barang & satuan yang sama sudah ada, qty-nya dijumlahkan.
  Cart add(Product product, {double qty = 1, ProductUnit? unit}) {
    final i = indexOf(product, unit);
    if (i == -1) {
      return Cart._grouped([
        ...lines,
        CartLine(product: product, qty: qty, unit: unit),
      ], voucher);
    }
    return _replace(i, lines[i].copyWith(qty: lines[i].qty + qty));
  }

  int indexOf(Product product, ProductUnit? unit) =>
      lines.indexWhere((l) => l.sameItem(product, unit));

  /// Mengganti satuan baris [index]. Bila sudah ada baris barang yang sama
  /// dengan satuan itu, keduanya digabung.
  Cart setUnit(int index, ProductUnit? unit) {
    final line = lines[index];
    if (line.unit?.id == unit?.id) return this;
    final other = indexOf(line.product, unit);
    if (other == -1) {
      return _replace(index, line.copyWith(unit: () => unit));
    }
    final merged = _replace(
      other,
      lines[other].copyWith(qty: lines[other].qty + line.qty),
    );
    return merged.removeAt(index);
  }

  /// Qty ≤ 0 menghapus baris.
  Cart setQty(int index, double qty) {
    if (qty <= 0) return removeAt(index);
    return _replace(index, lines[index].copyWith(qty: qty));
  }

  Cart removeAt(int index) =>
      Cart._grouped([...lines]..removeAt(index), voucher);

  Cart withVoucher(Voucher? voucher) => Cart(lines: lines, voucher: voucher);

  Cart _replace(int index, CartLine line) =>
      Cart._grouped([...lines]..[index] = line, voucher);

  /// Mengisi [CartLine.groupBaseQty] setiap baris: jumlah satuan dasar
  /// barang yang sama di seluruh keranjang.
  factory Cart._grouped(List<CartLine> lines, Voucher? voucher) {
    final totals = <int, double>{};
    for (final l in lines) {
      totals.update(
        l.product.id,
        (v) => v + l.baseQty,
        ifAbsent: () => l.baseQty,
      );
    }
    return Cart(
      lines: [
        for (final l in lines)
          l.copyWith(groupBaseQty: () => totals[l.product.id]),
      ],
      voucher: voucher,
    );
  }
}
