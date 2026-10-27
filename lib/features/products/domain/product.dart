import 'package:flutter/foundation.dart';

import 'product_pricing.dart';
import 'tag.dart';

/// Barang beserta satuan dan kategorinya (hasil join).
@immutable
class Product {
  const Product({
    required this.id,
    required this.code,
    required this.name,
    this.barcode,
    this.unitId,
    this.unitName,
    required this.purchasePrice,
    required this.sellingPrice,
    int? defaultSellingPrice,
    required this.stock,
    required this.minStock,
    this.isActive = true,
    this.tags = const [],
    this.units = const [],
    this.tiers = const [],
  }) : defaultSellingPrice = defaultSellingPrice ?? sellingPrice;

  final int id;

  /// Di layar disebut "Barcode" (wajib, unik; mis. BMM0000001).
  final String code;

  /// Di layar disebut "Barcode bawaan" (opsional; barcode pabrik di kemasan).
  final String? barcode;
  final String name;
  final int? unitId;
  final String? unitName;
  final int purchasePrice;

  /// Harga jual di toko yang sedang dipakai (harga khusus toko, atau harga
  /// default bila toko tidak mengaturnya / dilihat untuk semua toko).
  final int sellingPrice;

  /// Harga jual default barang (`products.selling_price`).
  final int defaultSellingPrice;

  /// Stok di toko yang sedang dipakai, atau jumlah semua toko.
  final double stock;
  final double minStock;
  final bool isActive;

  /// Kategori barang (bisa lebih dari satu, berwarna), urut nama. Di kode
  /// dan database disebut "tag"; di layar disebut "Kategori".
  final List<Tag> tags;

  /// Satuan lain (multi-satuan), urut isi terkecil.
  final List<ProductUnit> units;

  /// Harga grosir satuan dasar, urut jumlah minimal terkecil.
  final List<PriceTier> tiers;

  ProductUnit? unitById(int? id) {
    if (id == null) return null;
    for (final u in units) {
      if (u.id == id) return u;
    }
    return null;
  }

  bool get isLowStock => stock <= minStock;

  /// Toko ini memakai harga khusus (berbeda dari harga default).
  bool get hasStorePrice => sellingPrice != defaultSellingPrice;

  /// Untung per satuan (bisa negatif bila harga jual di bawah harga beli).
  int get margin => sellingPrice - purchasePrice;

  @override
  bool operator ==(Object other) => other is Product && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Isian form/import barang. Kategori ([tagNames]) dan satuan berupa nama;
/// yang belum ada dibuat otomatis saat disimpan.
@immutable
class ProductDraft {
  const ProductDraft({
    required this.code,
    this.barcode,
    required this.name,
    this.unitName,
    this.purchasePrice = 0,
    required this.sellingPrice,
    this.minStock = 0,
    this.isActive = true,
    this.tagNames,
    this.units,
    this.tiers,
  });

  final String code;
  final String? barcode;
  final String name;
  final String? unitName;
  final int purchasePrice;

  /// Harga jual default (toko bisa punya harga sendiri).
  final int sellingPrice;
  final double minStock;
  final bool isActive;

  /// Nama kategori (yang belum ada dibuat otomatis). `null` = kategori tidak
  /// diubah (mis. kolom Kategori tidak ada di file import).
  final List<String>? tagNames;

  /// Satuan lain (diganti semua); `null` = tidak diubah.
  final List<ProductUnit>? units;

  /// Harga grosir (diganti semua); `null` = tidak diubah.
  final List<PriceTier>? tiers;
}

/// Stok dan harga khusus satu toko, diisi di form barang admin.
@immutable
class StoreProductValues {
  const StoreProductValues({
    required this.storeId,
    required this.stock,
    this.price,
    this.unitPrices,
    this.tiers,
  });

  final int storeId;
  final double stock;

  /// `null` = memakai harga default barang.
  final int? price;

  /// Harga khusus toko per satuan lain (nama satuan huruf besar → harga;
  /// `null` = harga satuan itu). `null` = tidak diubah.
  final Map<String, int?>? unitPrices;

  /// Grosir khusus toko ini; kosong = ikut grosir semua toko. `null` =
  /// tidak diubah.
  final List<PriceTier>? tiers;
}

/// Stok & harga tersimpan satu toko (form barang, konfirmasi perubahan).
@immutable
class StoreProductSaved {
  const StoreProductSaved({
    this.stock = 0,
    this.price,
    this.unitPrices = const {},
    this.tiers = const [],
  });

  final double stock;

  /// Harga khusus toko; `null` = harga default.
  final int? price;

  /// Nama satuan lain (huruf besar) → harga khusus toko.
  final Map<String, int> unitPrices;

  /// Grosir khusus toko (kosong = ikut grosir semua toko).
  final List<PriceTier> tiers;
}

/// Validasi isian barang. Setiap fungsi mengembalikan pesan error atau `null`.
class ProductRules {
  const ProductRules._();

  static String? code(String v) {
    final c = v.trim();
    if (c.isEmpty) return 'Barcode wajib diisi.';
    if (c.length > 40) return 'Barcode maksimal 40 karakter.';
    return null;
  }

  static String? barcode(String? v) {
    final b = v?.trim() ?? '';
    if (b.isEmpty) return null;
    if (b.length > 40) return 'Barcode bawaan maksimal 40 karakter.';
    if (b.contains(RegExp(r'\s'))) {
      return 'Barcode bawaan tidak boleh berisi spasi.';
    }
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
  code('Barcode'),
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
    this.tagId,
    this.lowStockOnly = false,
    this.status = ProductStatusFilter.active,
    this.sort = ProductSort.name,
    this.storeId,
  });

  /// Stok & harga mengikuti toko ini; `null` = semua toko (stok dijumlah,
  /// harga default).
  final int? storeId;

  final String text;

  /// Hanya barang yang punya kategori (tag) ini.
  final int? tagId;
  final bool lowStockOnly;
  final ProductStatusFilter status;
  final ProductSort sort;

  ProductFilter copyWith({
    String? text,
    int? Function()? tagId,
    bool? lowStockOnly,
    ProductStatusFilter? status,
    ProductSort? sort,
    int? Function()? storeId,
  }) => ProductFilter(
    text: text ?? this.text,
    tagId: tagId != null ? tagId() : this.tagId,
    lowStockOnly: lowStockOnly ?? this.lowStockOnly,
    status: status ?? this.status,
    sort: sort ?? this.sort,
    storeId: storeId != null ? storeId() : this.storeId,
  );

  @override
  bool operator ==(Object other) =>
      other is ProductFilter &&
      other.text == text &&
      other.tagId == tagId &&
      other.lowStockOnly == lowStockOnly &&
      other.status == status &&
      other.sort == sort &&
      other.storeId == storeId;

  @override
  int get hashCode =>
      Object.hash(text, tagId, lowStockOnly, status, sort, storeId);
}
