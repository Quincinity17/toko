import 'package:flutter/foundation.dart';

/// Barang beserta nama kategori dan satuannya (hasil join).
@immutable
class Product {
  const Product({
    required this.id,
    required this.code,
    required this.name,
    this.barcode,
    this.categoryName,
    this.unitName,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.stock,
    required this.minStock,
  });

  final int id;
  final String code;
  final String? barcode;
  final String name;
  final String? categoryName;
  final String? unitName;
  final int purchasePrice;
  final int sellingPrice;
  final double stock;
  final double minStock;

  bool get isLowStock => stock <= minStock;

  @override
  bool operator ==(Object other) => other is Product && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
