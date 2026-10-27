import 'package:flutter/foundation.dart';

import '../../products/domain/product.dart';
import '../../products/domain/product_pricing.dart';

/// Ukuran kertas & susunan label (semua dalam milimeter). Label disusun di
/// tengah halaman; [gapX]/[gapY] = jarak antar label.
@immutable
class LabelLayout {
  const LabelLayout({
    required this.id,
    required this.name,
    required this.pageWidth,
    required this.pageHeight,
    required this.columns,
    required this.rows,
    required this.labelWidth,
    required this.labelHeight,
    this.gapX = 0,
    this.gapY = 0,
  });

  /// Rol label printer thermal: satu halaman = satu label.
  const LabelLayout.roll({
    required this.id,
    required this.name,
    required double width,
    required double height,
  }) : pageWidth = width,
       pageHeight = height,
       columns = 1,
       rows = 1,
       labelWidth = width,
       labelHeight = height,
       gapX = 0,
       gapY = 0;

  final String id;
  final String name;
  final double pageWidth;
  final double pageHeight;
  final int columns;
  final int rows;
  final double labelWidth;
  final double labelHeight;
  final double gapX;
  final double gapY;

  int get perPage => columns * rows;

  /// Satu halaman = satu label (rol label printer).
  bool get isRoll => perPage == 1;

  double get marginLeft =>
      (pageWidth - columns * labelWidth - (columns - 1) * gapX) / 2;

  double get marginTop =>
      (pageHeight - rows * labelHeight - (rows - 1) * gapY) / 2;

  /// Posisi kiri-atas label ke-[slot] (0 = kiri atas) di halamannya.
  ({double x, double y}) origin(int slot) {
    final i = slot % perPage;
    final col = i % columns;
    final row = i ~/ columns;
    return (
      x: marginLeft + col * (labelWidth + gapX),
      y: marginTop + row * (labelHeight + gapY),
    );
  }

  static const presets = <LabelLayout>[
    LabelLayout(
      id: 'a4-3x8',
      name: 'Stiker A4 · 3 × 8 (63,5 × 33,9 mm)',
      pageWidth: 210,
      pageHeight: 297,
      columns: 3,
      rows: 8,
      labelWidth: 63.5,
      labelHeight: 33.9,
      gapX: 2.5,
    ),
    LabelLayout(
      id: 'a4-4x10',
      name: 'Stiker A4 · 4 × 10 (48,5 × 25,4 mm)',
      pageWidth: 210,
      pageHeight: 297,
      columns: 4,
      rows: 10,
      labelWidth: 48.5,
      labelHeight: 25.4,
    ),
    LabelLayout(
      id: 'a4-5x13',
      name: 'Stiker A4 · 5 × 13 (38,1 × 21,2 mm)',
      pageWidth: 210,
      pageHeight: 297,
      columns: 5,
      rows: 13,
      labelWidth: 38.1,
      labelHeight: 21.2,
      gapX: 2.5,
    ),
    LabelLayout.roll(
      id: 'roll-50x30',
      name: 'Rol label printer · 50 × 30 mm',
      width: 50,
      height: 30,
    ),
    LabelLayout.roll(
      id: 'roll-40x30',
      name: 'Rol label printer · 40 × 30 mm',
      width: 40,
      height: 30,
    ),
    LabelLayout.roll(
      id: 'roll-58x40',
      name: 'Rol label printer · 58 × 40 mm',
      width: 58,
      height: 40,
    ),
  ];

  static LabelLayout byId(String? id) =>
      presets.firstWhere((p) => p.id == id, orElse: () => presets.first);
}

/// Satu barang yang dicetak labelnya.
@immutable
class LabelItem {
  const LabelItem({
    required this.productId,
    this.unitId,
    required this.name,
    required this.code,
    required this.price,
    this.unitName,
    this.copies = 1,
    this.factoryCode,
  });

  /// Label barang [p] (atau kemasan [unit]: barcode & harga kemasan).
  factory LabelItem.of(Product p, {ProductUnit? unit, int copies = 1}) =>
      LabelItem(
        productId: p.id,
        unitId: unit?.id,
        name: p.name,
        code: unit?.barcode ?? p.code,
        factoryCode: unit == null ? p.barcode : null,
        price: unit?.price ?? p.sellingPrice,
        unitName: unit?.name,
        copies: copies,
      );

  final int productId;

  /// Satuan lain (label kemasan, mis. DUS); `null` = satuan dasar.
  final int? unitId;
  final String name;

  /// Isi barcode yang dicetak (barcode barang / barcode kemasan).
  final String code;

  /// Barcode pabrik barang (dipakai bila [LabelOptions.useFactoryBarcode]).
  final String? factoryCode;
  final int price;
  final String? unitName;
  final int copies;

  LabelItem copyWith({int? copies}) => LabelItem(
    productId: productId,
    unitId: unitId,
    name: name,
    code: code,
    price: price,
    unitName: unitName,
    copies: copies ?? this.copies,
    factoryCode: factoryCode,
  );

  bool sameAs(LabelItem other) =>
      other.productId == productId && other.unitId == unitId;
}

/// Isi label yang ditampilkan.
@immutable
class LabelOptions {
  const LabelOptions({
    this.showName = true,
    this.showPrice = true,
    this.storeName,
    this.startAt = 1,
    this.useFactoryBarcode = false,
  });

  /// Cetak barcode pabrik (EAN) bila barang punya; lainnya barcode toko.
  final bool useFactoryBarcode;

  /// Barcode yang dicetak untuk [item].
  String codeOf(LabelItem item) =>
      useFactoryBarcode ? item.factoryCode ?? item.code : item.code;

  final bool showName;
  final bool showPrice;

  /// Nama toko di atas label; `null` = tidak dicetak.
  final String? storeName;

  /// Mulai dari label ke-berapa di halaman pertama (kertas stiker yang
  /// sebagian sudah terpakai). 1 = kiri atas.
  final int startAt;
}

/// Jumlah halaman untuk [labels] label mulai dari slot [startAt].
int labelPageCount(LabelLayout layout, int labels, {int startAt = 1}) {
  if (labels <= 0) return 0;
  final skip = (startAt - 1).clamp(0, layout.perPage - 1);
  return ((skip + labels) / layout.perPage).ceil();
}
