import 'package:flutter/foundation.dart';

/// Barang beserta nama kategori dan satuannya (hasil join).
@immutable
class Product {
  const Product({
    required this.id,
    required this.code,
    required this.name,
    this.barcode,
    this.categoryId,
    this.categoryName,
    this.unitId,
    this.unitName,
    required this.purchasePrice,
    required this.sellingPrice,
    required this.stock,
    required this.minStock,
    this.isActive = true,
  });

  final int id;
  final String code;
  final String? barcode;
  final String name;
  final int? categoryId;
  final String? categoryName;
  final int? unitId;
  final String? unitName;
  final int purchasePrice;
  final int sellingPrice;
  final double stock;
  final double minStock;
  final bool isActive;

  bool get isLowStock => stock <= minStock;

  /// Untung per satuan (bisa negatif bila harga jual di bawah harga beli).
  int get margin => sellingPrice - purchasePrice;

  @override
  bool operator ==(Object other) => other is Product && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Isian form/import barang. Kategori dan satuan berupa nama; yang belum ada
/// dibuat otomatis saat disimpan.
@immutable
class ProductDraft {
  const ProductDraft({
    required this.code,
    this.barcode,
    required this.name,
    this.categoryName,
    this.unitName,
    this.purchasePrice = 0,
    required this.sellingPrice,
    this.stock = 0,
    this.minStock = 0,
    this.isActive = true,
  });

  final String code;
  final String? barcode;
  final String name;
  final String? categoryName;
  final String? unitName;
  final int purchasePrice;
  final int sellingPrice;
  final double stock;
  final double minStock;
  final bool isActive;
}

/// Validasi isian barang. Setiap fungsi mengembalikan pesan error atau `null`.
class ProductRules {
  const ProductRules._();

  static String? code(String v) {
    final c = v.trim();
    if (c.isEmpty) return 'Kode wajib diisi.';
    if (c.length > 40) return 'Kode maksimal 40 karakter.';
    return null;
  }

  static String? barcode(String? v) {
    final b = v?.trim() ?? '';
    if (b.isEmpty) return null;
    if (b.length > 40) return 'Barcode maksimal 40 karakter.';
    if (b.contains(RegExp(r'\s'))) return 'Barcode tidak boleh berisi spasi.';
    return null;
  }

  static String? name(String v) {
    final n = v.trim();
    if (n.isEmpty) return 'Nama wajib diisi.';
    if (n.length > 150) return 'Nama maksimal 150 karakter.';
    return null;
  }

  static String? price(num? v, {required String label}) {
    if (v == null) return '$label wajib diisi.';
    if (v < 0) return '$label tidak boleh negatif.';
    return null;
  }

  static String? minStock(num? v) {
    if (v != null && v < 0) return 'Stok minimum tidak boleh negatif.';
    return null;
  }

  /// Peringatan (bukan error): harga jual di bawah harga beli.
  static String? marginWarning(int purchase, int selling) {
    if (selling < purchase) {
      return 'Harga jual lebih rendah dari harga beli (rugi per barang).';
    }
    return null;
  }
}

enum ProductSort {
  name('Nama A–Z'),
  code('Kode'),
  stockLow('Stok terkecil'),
  priceHigh('Harga jual tertinggi'),
  updated('Terakhir diubah');

  const ProductSort(this.label);

  final String label;
}

enum ProductStatusFilter {
  active('Aktif'),
  inactive('Nonaktif'),
  all('Semua');

  const ProductStatusFilter(this.label);

  final String label;
}

/// Filter daftar barang di halaman Produk.
@immutable
class ProductFilter {
  const ProductFilter({
    this.text = '',
    this.categoryId,
    this.lowStockOnly = false,
    this.status = ProductStatusFilter.active,
    this.sort = ProductSort.name,
  });

  final String text;
  final int? categoryId;
  final bool lowStockOnly;
  final ProductStatusFilter status;
  final ProductSort sort;

  ProductFilter copyWith({
    String? text,
    int? Function()? categoryId,
    bool? lowStockOnly,
    ProductStatusFilter? status,
    ProductSort? sort,
  }) => ProductFilter(
    text: text ?? this.text,
    categoryId: categoryId != null ? categoryId() : this.categoryId,
    lowStockOnly: lowStockOnly ?? this.lowStockOnly,
    status: status ?? this.status,
    sort: sort ?? this.sort,
  );

  @override
  bool operator ==(Object other) =>
      other is ProductFilter &&
      other.text == text &&
      other.categoryId == categoryId &&
      other.lowStockOnly == lowStockOnly &&
      other.status == status &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(text, categoryId, lowStockOnly, status, sort);
}
