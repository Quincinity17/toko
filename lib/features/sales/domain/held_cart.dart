import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'cart.dart';

/// Satu barang di transaksi tertahan. Kode dan nama disalin agar tetap bisa
/// ditampilkan walau barangnya kemudian dihapus/dinonaktifkan.
@immutable
class HeldItem {
  const HeldItem({
    required this.productId,
    required this.code,
    required this.name,
    required this.qty,
    this.unitId,
    this.unitName,
  });

  final int productId;
  final String code;
  final String name;
  final double qty;

  /// Satuan lain (multi-satuan); `null` = satuan dasar.
  final int? unitId;
  final String? unitName;

  Map<String, Object> toJson() => {
    'id': productId,
    'code': code,
    'name': name,
    'qty': qty,
    'unit': ?unitId,
    'unitName': ?unitName,
  };

  factory HeldItem.fromJson(Map<String, dynamic> json) => HeldItem(
    productId: json['id'] as int,
    code: json['code'] as String,
    name: json['name'] as String,
    qty: (json['qty'] as num).toDouble(),
    unitId: json['unit'] as int?,
    unitName: json['unitName'] as String?,
  );

  static String encodeCart(Cart cart) => jsonEncode([
    for (final l in cart.lines)
      HeldItem(
        productId: l.product.id,
        code: l.product.code,
        name: l.product.name,
        qty: l.qty,
        unitId: l.unit?.id,
        unitName: l.unit?.name,
      ).toJson(),
  ]);

  static List<HeldItem> decodeList(String json) => [
    for (final e in jsonDecode(json) as List)
      HeldItem.fromJson(e as Map<String, dynamic>),
  ];
}

/// Transaksi yang ditahan (mis. pelanggan masih lihat-lihat).
@immutable
class HeldCart {
  const HeldCart({
    required this.id,
    required this.note,
    required this.cashierName,
    required this.items,
    required this.total,
    required this.createdAt,
  });

  final int id;
  final String? note;
  final String cashierName;
  final List<HeldItem> items;

  /// Total saat ditahan. Saat dilanjutkan, harga mengikuti harga terbaru.
  final int total;
  final DateTime createdAt;
}

/// Hasil melanjutkan transaksi tertahan.
@immutable
class ResumedCart {
  const ResumedCart({required this.cart, required this.skipped});

  final Cart cart;

  /// Nama barang yang tidak bisa dimasukkan lagi (dihapus/dinonaktifkan).
  final List<String> skipped;
}
