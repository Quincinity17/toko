import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';

/// Satuan lain sebuah barang (multi-satuan), mis. DUS isi 24 PCS. Stok tetap
/// dihitung dalam satuan dasar barang; harga berlaku di semua toko.
@immutable
class ProductUnit {
  const ProductUnit({
    this.id,
    required this.name,
    required this.factor,
    this.barcode,
    required this.price,
    int? defaultPrice,
  }) : defaultPrice = defaultPrice ?? price;

  /// `null` = belum tersimpan (isian form).
  final int? id;

  /// Huruf besar (DUS, PAK, LUSIN).
  final String name;

  /// Isi satu satuan ini dalam satuan dasar.
  final double factor;

  /// Barcode kemasan (opsional). Scan barcode ini di kasir = 1 [name].
  final String? barcode;

  /// Harga di toko yang sedang dipakai (harga khusus toko, atau default).
  final int price;

  /// Harga satuan ini untuk semua toko (`product_units.selling_price`).
  final int defaultPrice;

  @override
  bool operator ==(Object other) =>
      other is ProductUnit &&
      other.id == id &&
      other.name == name &&
      other.factor == factor &&
      other.barcode == barcode &&
      other.price == price;

  @override
  int get hashCode => Object.hash(id, name, factor, barcode, price);
}

/// Harga grosir/bertingkat satuan dasar: beli minimal [minQty] → [price] per
/// satuan. Berlaku di semua toko.
@immutable
class PriceTier {
  const PriceTier({required this.minQty, required this.price});

  final double minQty;
  final int price;

  @override
  bool operator ==(Object other) =>
      other is PriceTier && other.minQty == minQty && other.price == price;

  @override
  int get hashCode => Object.hash(minQty, price);
}

/// Aturan multi-satuan & harga grosir (dipakai form dan repository).
class PricingRules {
  const PricingRules._();

  /// Harga grosir yang berlaku untuk [qty]: jumlah minimal terbesar yang
  /// ≤ [qty]; `null` bila belum mencapai tingkat mana pun.
  static PriceTier? tierFor(List<PriceTier> tiers, double qty) {
    PriceTier? best;
    for (final t in tiers) {
      if (qty + 1e-9 >= t.minQty && (best == null || t.minQty > best.minQty)) {
        best = t;
      }
    }
    return best;
  }

  /// Satuan disimpan huruf besar tanpa spasi di ujung.
  static String unitName(String v) => v.trim().toUpperCase();

  /// Error pertama satuan lain, atau `null`. [code]/[barcode] = barcode
  /// barang itu sendiri (barcode kemasan tidak boleh sama).
  static String? units(
    List<ProductUnit> units, {
    String? baseUnit,
    required String code,
    String? barcode,
  }) {
    final base = unitName(baseUnit ?? '');
    final names = <String>{};
    final barcodes = <String>{};
    for (final u in units) {
      final name = unitName(u.name);
      if (name.isEmpty) return 'Nama satuan lain wajib diisi.';
      if (name.length > 20) return 'Nama satuan maksimal 20 karakter.';
      if (name == (base.isEmpty ? 'PCS' : base)) {
        return 'Satuan $name sama dengan satuan dasar barang.';
      }
      if (!names.add(name)) return 'Satuan $name ditulis lebih dari sekali.';
      if (!(u.factor > 0) || u.factor == 1) {
        return 'Isi satuan $name harus lebih dari 0 dan bukan 1.';
      }
      if (u.price < 0) return 'Harga satuan $name tidak boleh negatif.';
      final b = u.barcode?.trim() ?? '';
      if (b.isEmpty) continue;
      if (b.length > 40) return 'Barcode satuan $name maksimal 40 karakter.';
      if (b.contains(RegExp(r'\s'))) {
        return 'Barcode satuan $name tidak boleh berisi spasi.';
      }
      if (b.toLowerCase() == code.trim().toLowerCase() ||
          b == barcode?.trim()) {
        return 'Barcode satuan $name sama dengan barcode barang ini.';
      }
      if (!barcodes.add(b)) return 'Barcode $b dipakai dua satuan.';
    }
    return null;
  }

  /// Error pertama harga grosir, atau `null`. Harga grosir harus lebih
  /// murah dari [sellingPrice] (harga jual default).
  static String? tiers(List<PriceTier> tiers, {required int sellingPrice}) {
    final seen = <double>{};
    for (final t in tiers) {
      if (!(t.minQty > 1)) {
        return 'Jumlah minimal harga grosir harus lebih dari 1.';
      }
      if (!seen.add(t.minQty)) {
        return 'Jumlah minimal ${Fmt.number(t.minQty)} ditulis lebih dari '
            'sekali.';
      }
      if (t.price < 0) return 'Harga grosir tidak boleh negatif.';
      if (t.price >= sellingPrice) {
        return 'Harga grosir (min. ${Fmt.number(t.minQty)}) harus lebih murah '
            'dari harga jual ${Fmt.rupiah(sellingPrice)}.';
      }
    }
    return null;
  }
}

/// Satuan lain & harga grosir sebagai teks satu sel (import/export Excel):
/// - Satuan lain: `DUS:24:78000:8991002101234; PAK:6:20000`
///   (nama : isi : harga : barcode kemasan opsional)
/// - Harga grosir: `10:3300; 24:3100` (beli minimal : harga)
abstract final class PricingText {
  static String _n(num v) =>
      v == v.roundToDouble() ? '${v.round()}' : '$v'.replaceAll('.', ',');

  static String units(List<ProductUnit> units) => [
    for (final u in units)
      [u.name, _n(u.factor), '${u.price}', ?u.barcode].join(':'),
  ].join('; ');

  static String tiers(List<PriceTier> tiers) =>
      [for (final t in tiers) '${_n(t.minQty)}:${t.price}'].join('; ');

  static List<String> _parts(String text) => [
    for (final p in text.split(RegExp(r'[;\n]')))
      if (p.trim().isNotEmpty) p.trim(),
  ];

  static num? _num(String v) {
    final t = v.trim().replaceAll(RegExp(r'^rp\s*', caseSensitive: false), '');
    if (t.isEmpty) return null;
    // "78.000" / "1,5" (format Indonesia) atau "78000".
    return num.tryParse(t.replaceAll('.', '').replaceAll(',', '.'));
  }

  /// Satuan lain dari teks; error = pesan.
  static ({List<ProductUnit> units, String? error}) parseUnits(String text) {
    final out = <ProductUnit>[];
    for (final part in _parts(text)) {
      final f = part.split(RegExp(r'\s*[:=]\s*'));
      if (f.length < 3 || f.length > 4) {
        return (
          units: const [],
          error: 'Satuan lain "$part": tulis NAMA:ISI:HARGA[:BARCODE].',
        );
      }
      final factor = _num(f[1]);
      final price = _num(f[2]);
      if (factor == null || price == null) {
        return (
          units: const [],
          error: 'Satuan lain "$part": isi & harga harus angka.',
        );
      }
      out.add(
        ProductUnit(
          name: PricingRules.unitName(f[0]),
          factor: factor.toDouble(),
          price: price.round(),
          barcode: f.length == 4 && f[3].trim().isNotEmpty ? f[3].trim() : null,
        ),
      );
    }
    return (units: out, error: null);
  }

  /// Harga grosir dari teks; error = pesan.
  static ({List<PriceTier> tiers, String? error}) parseTiers(String text) {
    final out = <PriceTier>[];
    for (final part in _parts(text)) {
      final f = part.split(RegExp(r'\s*[:=]\s*'));
      final min = f.length == 2 ? _num(f[0]) : null;
      final price = f.length == 2 ? _num(f[1]) : null;
      if (min == null || price == null) {
        return (
          tiers: const [],
          error: 'Harga grosir "$part": tulis MINIMAL:HARGA, mis. 10:3300.',
        );
      }
      out.add(PriceTier(minQty: min.toDouble(), price: price.round()));
    }
    return (tiers: out, error: null);
  }
}
