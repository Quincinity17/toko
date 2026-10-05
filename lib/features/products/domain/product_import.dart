import 'package:flutter/foundation.dart';

import '../../../core/utils/number_input.dart';
import 'product.dart';
import 'tag.dart';

/// Kolom data barang di file import/export. [label] juga menjadi judul kolom
/// file export dan template, sehingga hasil export bisa langsung di-import.
enum ProductField {
  // Di layar: kode = "Barcode", barcode = "Barcode bawaan". Kolom "Barcode"
  // hanya menjadi kode bila file tidak punya kolom kode (mis. Kode Item
  // iPOS); jika ada, kolom "Barcode" menjadi barcode bawaan. Urutan sinonim
  // penting: dicoba dari depan.
  code(
    'Barcode',
    required: true,
    synonyms: [
      'kode',
      'kode item',
      'kode barang',
      'kode produk',
      'kodeitem',
      'item code',
      'sku',
      'plu',
      'id barang',
      'barcode',
    ],
  ),
  barcode(
    'Barcode Bawaan',
    synonyms: [
      'barcode bawaan',
      'barcode pabrik',
      'kode barcode',
      'barcode 1',
      'ean',
      'upc',
      'kode scan',
      'barcode',
    ],
  ),
  name(
    'Nama',
    required: true,
    synonyms: [
      'nama',
      'nama item',
      'nama barang',
      'nama produk',
      'namaitem',
      'item name',
      'produk',
      'keterangan',
      'deskripsi',
    ],
  ),

  /// Satu atau beberapa kategori dipisah koma, mis. "Mainan, Boneka".
  category(
    'Kategori',
    synonyms: [
      'kategori',
      'jenis',
      'jenis barang',
      'group',
      'grup',
      'golongan',
      'kelompok',
      'departemen',
      'dept',
      'tag',
      'tags',
      'label',
    ],
  ),
  unit(
    'Satuan',
    synonyms: ['satuan', 'satuan dasar', 'satuan kecil', 'unit', 'sat', 'uom'],
  ),
  purchasePrice(
    'Harga Beli',
    synonyms: [
      'harga beli',
      'harga pokok',
      'hpp',
      'modal',
      'harga modal',
      'cost',
      'harga beli terakhir',
      'h beli',
    ],
  ),
  sellingPrice(
    'Harga Jual',
    required: true,
    synonyms: [
      'harga jual',
      'harga jual 1',
      'harga jual umum',
      'harga ecer',
      'harga',
      'price',
      'hj',
      'h jual',
    ],
  ),
  stock(
    'Stok',
    synonyms: [
      'stok',
      'stock',
      'stok akhir',
      'qty',
      'jumlah',
      'saldo',
      'persediaan',
    ],
  ),
  minStock(
    'Stok Minimum',
    synonyms: [
      'stok minimum',
      'stok min',
      'min stok',
      'stok minimal',
      'minimum',
      'stock min',
      'min stock',
    ],
  ),
  isActive('Aktif', synonyms: ['aktif', 'status', 'active']);

  const ProductField(
    this.label, {
    this.required = false,
    this.synonyms = const [],
  });

  final String label;
  final bool required;
  final List<String> synonyms;
}

/// Isi file yang sudah dibaca: judul kolom dan baris (semua berupa teks).
@immutable
class ImportTable {
  const ImportTable({required this.headers, required this.rows});

  final List<String> headers;

  /// Tanpa baris judul. [rowNumberOffset] memberi nomor baris seperti di Excel.
  final List<List<String>> rows;

  /// Baris data pertama ada di baris ke-2 file (baris 1 = judul).
  static const rowNumberOffset = 2;

  String cell(int row, int? column) {
    if (column == null) return '';
    final r = rows[row];
    return column < r.length ? r[column].trim() : '';
  }
}

/// Pasangan kolom data barang → indeks kolom di file.
typedef ImportMapping = Map<ProductField, int?>;

String _normalize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

/// Menebak kolom file untuk setiap data barang berdasarkan judul kolom
/// (termasuk nama kolom export iPOS). Kecocokan persis didahulukan, lalu
/// judul yang mengandung sinonim. Satu kolom file hanya dipakai sekali.
ImportMapping guessMapping(List<String> headers) {
  final normalized = headers.map(_normalize).toList();
  final mapping = <ProductField, int?>{
    for (final f in ProductField.values) f: null,
  };
  final used = <int>{};

  void assign(bool Function(String header, String synonym) matches) {
    for (final field in ProductField.values) {
      if (mapping[field] != null) continue;
      outer:
      for (final syn in field.synonyms) {
        for (var i = 0; i < normalized.length; i++) {
          if (!used.contains(i) && matches(normalized[i], syn)) {
            mapping[field] = i;
            used.add(i);
            break outer;
          }
        }
      }
    }
  }

  assign((h, s) => h == s);
  assign((h, s) => h.startsWith('$s ') || h.endsWith(' $s'));
  return mapping;
}

/// Apa yang dilakukan pada barang yang kodenya sudah ada di database.
enum ExistingProductAction {
  skip('Lewati', 'Barang yang sudah ada tidak diubah.'),
  overwrite(
    'Timpa semua data',
    'Nama, kategori, harga, stok, dll. diganti isi file.',
  ),
  updateStockPrice(
    'Update stok & harga saja',
    'Hanya harga beli, harga jual, dan stok yang diganti.',
  );

  const ExistingProductAction(this.label, this.description);

  final String label;
  final String description;
}

/// Satu baris file setelah diperiksa.
@immutable
class ImportRow {
  const ImportRow({
    required this.rowNumber,
    this.draft,
    this.errors = const [],
    this.existingId,
    this.provided = const {},
    this.stock = 0,
  });

  /// Nomor baris di file (seperti di Excel).
  final int rowNumber;
  final ProductDraft? draft;
  final List<String> errors;

  /// Id barang di database dengan kode yang sama (null = barang baru).
  final int? existingId;

  /// Kolom yang benar-benar terisi di file (untuk "update stok & harga").
  final Set<ProductField> provided;

  /// Stok dari file, untuk toko tujuan import.
  final double stock;

  bool get isValid => errors.isEmpty;
  bool get isNew => isValid && existingId == null;
  bool get isExisting => isValid && existingId != null;
}

/// Kode/barcode yang sudah ada di database, untuk pemeriksaan sebelum import.
class ExistingIndex {
  ExistingIndex({required this.idByCode, required this.idByBarcode});

  /// Kunci huruf kecil.
  final Map<String, int> idByCode;
  final Map<String, int> idByBarcode;
}

/// Memeriksa semua baris: kolom wajib, format angka, duplikat di dalam file,
/// dan barcode yang sudah dipakai barang lain.
List<ImportRow> validateImport(
  ImportTable table,
  ImportMapping mapping,
  ExistingIndex existing,
) {
  final result = <ImportRow>[];
  final seenCode = <String, int>{};
  final seenBarcode = <String, int>{};

  for (var i = 0; i < table.rows.length; i++) {
    final rowNumber = i + ImportTable.rowNumberOffset;
    String cell(ProductField f) => table.cell(i, mapping[f]);

    // Baris kosong di tengah file diabaikan tanpa error.
    if (ProductField.values.every((f) => cell(f).isEmpty)) continue;

    final errors = <String>[];
    final provided = {
      for (final f in ProductField.values)
        if (mapping[f] != null && cell(f).isNotEmpty) f,
    };

    num? number(ProductField f, {bool integer = false}) {
      final raw = cell(f);
      if (raw.isEmpty) return null;
      final v = parseIdNumber(raw);
      if (v == null) {
        errors.add('${f.label} "$raw" bukan angka.');
        return null;
      }
      if (v < 0) {
        errors.add('${f.label} tidak boleh negatif.');
        return null;
      }
      return integer ? v.round() : v;
    }

    final code = cell(ProductField.code);
    final name = cell(ProductField.name);
    final barcode = cell(ProductField.barcode);
    if (code.isEmpty) errors.add('Barcode kosong.');
    if (name.isEmpty) errors.add('Nama kosong.');
    final codeError = code.isEmpty ? null : ProductRules.code(code);
    if (codeError != null) errors.add(codeError);
    final nameError = name.isEmpty ? null : ProductRules.name(name);
    if (nameError != null) errors.add(nameError);
    final barcodeError = ProductRules.barcode(barcode);
    if (barcodeError != null) errors.add(barcodeError);

    final sell = number(ProductField.sellingPrice, integer: true);
    if (cell(ProductField.sellingPrice).isEmpty) {
      errors.add('Harga jual kosong.');
    }
    final buy = number(ProductField.purchasePrice, integer: true);
    final stock = number(ProductField.stock);
    final minStock = number(ProductField.minStock);

    final codeKey = code.toLowerCase();
    if (code.isNotEmpty) {
      final first = seenCode[codeKey];
      if (first != null) {
        errors.add('Barcode "$code" duplikat dengan baris $first.');
      } else {
        seenCode[codeKey] = rowNumber;
      }
    }
    final existingId = existing.idByCode[codeKey];
    if (barcode.isNotEmpty) {
      final first = seenBarcode[barcode];
      if (first != null) {
        errors.add('Barcode bawaan $barcode duplikat dengan baris $first.');
      } else {
        seenBarcode[barcode] = rowNumber;
      }
      final owner = existing.idByBarcode[barcode];
      if (owner != null && owner != existingId) {
        errors.add('Barcode bawaan $barcode sudah dipakai barang lain.');
      }
    }

    final categories = TagRules.split(cell(ProductField.category));
    for (final t in categories) {
      final tagError = TagRules.name(t);
      if (tagError != null) errors.add('Kategori "$t": $tagError');
    }

    final active = cell(ProductField.isActive).toLowerCase();
    final isActive = ![
      '0',
      'tidak',
      'no',
      'false',
      'nonaktif',
      'n',
    ].contains(active);

    result.add(
      ImportRow(
        rowNumber: rowNumber,
        errors: errors,
        existingId: existingId,
        provided: provided,
        stock: (stock ?? 0).toDouble(),
        draft: errors.isNotEmpty
            ? null
            : ProductDraft(
                code: code,
                barcode: barcode.isEmpty ? null : barcode,
                name: name,
                unitName: cell(ProductField.unit),
                purchasePrice: (buy ?? 0).toInt(),
                sellingPrice: sell!.toInt(),
                minStock: (minStock ?? 0).toDouble(),
                isActive: isActive,
                // Kolom Kategori kosong/tidak ada = kategori barang tidak diubah.
                tagNames: provided.contains(ProductField.category)
                    ? categories
                    : null,
              ),
      ),
    );
  }
  return result;
}

/// Ringkasan hasil import.
@immutable
class ImportResult {
  const ImportResult({
    required this.inserted,
    required this.updated,
    required this.skipped,
    required this.failed,
    this.newCategories = 0,
    this.newUnits = 0,
  });

  final int inserted;
  final int updated;
  final int skipped;

  /// Baris yang tidak di-import karena error.
  final List<ImportRow> failed;
  final int newCategories;
  final int newUnits;

  int get succeeded => inserted + updated;
}
