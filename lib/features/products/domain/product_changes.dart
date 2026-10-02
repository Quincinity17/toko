import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';
import 'product.dart';

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
  required Map<int, ({double stock, int? price})> beforeStores,
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
  add('Kode', before.code, after.code.trim());
  add('Barcode', text(before.barcode, '–'), text(after.barcode, '–'));
  add(
    'Satuan',
    text(before.unitName, 'Tanpa satuan'),
    text(unitAfter, 'Tanpa satuan'),
  );
  add(
    'Harga beli',
    Fmt.rupiah(before.purchasePrice),
    Fmt.rupiah(after.purchasePrice),
  );
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
  }
  return out;
}
