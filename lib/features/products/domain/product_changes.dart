import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';
import 'product.dart';
import 'product_pricing.dart';

/// Satu isian yang berubah, untuk konfirmasi sebelum menyimpan.
@immutable
class FieldChange {
  const FieldChange(this.label, this.from, this.to);

  final String label;
  final String from;
  final String to;

  @override
  bool operator ==(Object other) =>
      other is FieldChange &&
      other.label == label &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(label, from, to);

  @override
  String toString() => '$label: $from → $to';
}

/// Daftar perubahan barang [before] (dengan stok/harga per toko
/// [beforeStores]) menjadi isian [after] / [afterStores]. Kosong = tidak ada
/// yang berubah. Nilai ditampilkan seperti di layar (Rp, "Tanpa kategori").
///
/// Harga toko yang sama dengan harga default dianggap "harga default",
/// sama seperti cara `ProductRepository.save` menyimpannya.
List<FieldChange> productChanges({
  required Product before,
  required Map<int, StoreProductSaved> beforeStores,
  required ProductDraft after,
  required List<StoreProductValues> afterStores,
  Map<int, String> storeNames = const {},
}) {
  final out = <FieldChange>[];
  void add(String label, String from, String to) {
    if (from != to) out.add(FieldChange(label, from, to));
  }

  String text(String? v, String empty) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? empty : t;
  }

  String tags(Iterable<String> names) {
    final list = names.map((n) => n.trim()).where((n) => n.isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list.isEmpty ? 'Tanpa kategori' : list.join(', ');
  }

  final unitAfter = after.unitName?.trim().toUpperCase();
  final unit = text(unitAfter ?? before.unitName, '');

  add('Nama', before.name, after.name.trim());
  add('Barcode', before.code, after.code.trim());
  add('Barcode bawaan', text(before.barcode, '–'), text(after.barcode, '–'));
  add(
    'Satuan',
    text(before.unitName, 'Tanpa satuan'),
    text(unitAfter, 'Tanpa satuan'),
  );
  // Harga beli opsional: 0 = belum diisi.
  String buy(int v) => v == 0 ? 'Belum diisi' : Fmt.rupiah(v);
  add('Harga beli', buy(before.purchasePrice), buy(after.purchasePrice));
  add(
    'Harga jual',
    Fmt.rupiah(before.defaultSellingPrice),
    Fmt.rupiah(after.sellingPrice),
  );
  add('Stok minimum', Fmt.number(before.minStock), Fmt.number(after.minStock));
  add(
    'Status',
    before.isActive ? 'Aktif' : 'Nonaktif',
    after.isActive ? 'Aktif' : 'Nonaktif',
  );
  if (after.tagNames != null) {
    // Kategori dicocokkan tanpa peduli huruf besar (seperti saat disimpan).
    final from = tags(before.tags.map((t) => t.name));
    final to = tags(after.tagNames!);
    if (from.toLowerCase() != to.toLowerCase()) {
      out.add(FieldChange('Kategori', from, to));
    }
  }

  if (after.units case final units?) {
    String text(List<ProductUnit> list) {
      final items = [
        for (final u in list)
          '${PricingRules.unitName(u.name)} isi ${Fmt.number(u.factor)} '
              '${Fmt.rupiah(u.defaultPrice)}'
              '${(u.barcode?.trim().isEmpty ?? true) ? '' : ' (${u.barcode!.trim()})'}',
      ]..sort();
      return items.isEmpty ? 'Tidak ada' : items.join(', ');
    }

    add('Satuan lain', text(before.units), text(units));
  }
  if (after.tiers case final tiers?) {
    String text(List<PriceTier> list) {
      final sorted = [...list]..sort((a, b) => a.minQty.compareTo(b.minQty));
      return sorted.isEmpty
          ? 'Tidak ada'
          : sorted
                .map(
                  (t) => 'min. ${Fmt.number(t.minQty)} ${Fmt.rupiah(t.price)}',
                )
                .join(', ');
    }

    add('Harga grosir', text(before.tiers), text(tiers));
  }

  String price(int? storePrice, int defaultPrice) =>
      storePrice == null || storePrice == defaultPrice
      ? 'Harga default'
      : Fmt.rupiah(storePrice);

  for (final v in afterStores) {
    final old = beforeStores[v.storeId];
    final name = storeNames[v.storeId] ?? 'toko';
    add(
      'Stok $name',
      '${Fmt.number(old?.stock ?? 0)} $unit'.trim(),
      '${Fmt.number(v.stock)} $unit'.trim(),
    );
    add(
      'Harga $name',
      price(old?.price, before.defaultSellingPrice),
      price(v.price, after.sellingPrice),
    );
    // Harga satuan lain khusus toko (sama dengan harga satuan = default).
    final defaults = {
      for (final u in after.units ?? before.units)
        PricingRules.unitName(u.name): u.defaultPrice,
    };
    for (final MapEntry(key: unit, value: p)
        in (v.unitPrices ?? const <String, int?>{}).entries) {
      String text(int? x) =>
          x == null || x == defaults[unit] ? 'Harga $unit' : Fmt.rupiah(x);
      add('Harga $unit $name', text(old?.unitPrices[unit]), text(p));
    }
    if (v.tiers case final tiers?) {
      String text(List<PriceTier> list) {
        final sorted = [...list]..sort((a, b) => a.minQty.compareTo(b.minQty));
        return sorted.isEmpty
            ? 'Ikut semua toko'
            : sorted
                  .map(
                    (t) =>
                        'min. ${Fmt.number(t.minQty)} ${Fmt.rupiah(t.price)}',
                  )
                  .join(', ');
      }

      add('Grosir $name', text(old?.tiers ?? const []), text(tiers));
    }
  }
  return out;
}
