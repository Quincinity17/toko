import 'dart:convert';

import '../../../core/utils/number_input.dart';
import 'product_import.dart';
import 'price_markup.dart';

/// Kolom halaman Input Tabel (Produk › Input Tabel): mengetik banyak barang
/// baru sekaligus tanpa membuka Excel. Pemeriksaan dan penyimpanan memakai
/// alur import ([validateImport], `ProductImportService`), jadi aturannya sama.
enum BulkColumn {
  code('Barcode', ProductField.code),
  barcode('Barcode bawaan', ProductField.barcode),
  name('Nama barang', ProductField.name),
  category('Kategori', ProductField.category),
  unit('Satuan', ProductField.unit),
  purchasePrice('Harga beli', ProductField.purchasePrice),

  /// Bantu hitung harga jual; tidak disimpan.
  markup('Untung %', null),
  sellingPrice('Harga jual', ProductField.sellingPrice),
  stock('Stok', ProductField.stock);

  const BulkColumn(this.label, this.field);

  final String label;
  final ProductField? field;

  bool get isMoney => this == purchasePrice || this == sellingPrice;
  bool get isNumber => isMoney || this == markup || this == stock;
}

/// Isi satu baris tabel (teks apa adanya, seperti sel Excel).
typedef BulkRowValues = Map<BulkColumn, String>;

abstract final class BulkEntry {
  /// Satuan bila kolom Satuan kosong (sama dengan form barang).
  static const defaultUnit = 'PCS';

  /// Draf tabel (baris yang terisi saja) sebagai JSON:
  /// `[{"code": "BMM…", "name": "…"}, …]`.
  static String encodeDraft(List<BulkRowValues> rows) => jsonEncode([
    for (final row in rows)
      if (!isBlank(row))
        {
          for (final MapEntry(:key, :value) in row.entries)
            if (value.trim().isNotEmpty) key.name: value,
        },
  ]);

  /// Kebalikan [encodeDraft]; JSON rusak / kolom tak dikenal diabaikan.
  static List<BulkRowValues> decodeDraft(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final byName = BulkColumn.values.asNameMap();
      return [
        for (final row in jsonDecode(json) as List)
          {
            for (final MapEntry(:key, :value) in (row as Map).entries)
              ?byName[key]: '$value',
          },
      ];
    } on FormatException {
      return const [];
    } on TypeError {
      return const [];
    }
  }

  static bool isBlank(BulkRowValues row) =>
      BulkColumn.values.every((c) => (row[c] ?? '').trim().isEmpty);

  /// Harga jual dari harga beli + untung % (lihat [PriceMarkup]); `null`
  /// bila salah satunya kosong / tidak valid.
  static int? sellingFromMarkup(BulkRowValues row) {
    final buy = parseIdNumber(row[BulkColumn.purchasePrice] ?? '');
    final pct = parseIdNumber(row[BulkColumn.markup] ?? '');
    if (buy == null || pct == null) return null;
    return PriceMarkup.sellingPrice(buy.round(), pct.toDouble());
  }

  /// Memeriksa baris tabel. [ImportRow.rowNumber] = nomor baris di tabel
  /// (mulai 1). Baris kosong dilewati. Barcode yang sudah dipakai barang
  /// lain = error (tabel ini hanya untuk barang baru; ubah barang lewat
  /// form).
  static List<ImportRow> validate(
    List<BulkRowValues> rows,
    ExistingIndex existing,
  ) {
    final columns = [
      for (final c in BulkColumn.values)
        if (c.field != null) c,
    ];
    final table = ImportTable(
      headers: [for (final c in columns) c.field!.label],
      rows: [
        for (final row in rows)
          [
            for (final c in columns)
              switch (c) {
                BulkColumn.unit
                    when (row[c] ?? '').trim().isEmpty && !isBlank(row) =>
                  defaultUnit,
                BulkColumn.sellingPrice when (row[c] ?? '').trim().isEmpty =>
                  sellingFromMarkup(row)?.toString() ?? '',
                _ => row[c] ?? '',
              },
          ],
      ],
    );
    final mapping = <ProductField, int?>{
      for (final f in ProductField.values) f: null,
      for (final (i, c) in columns.indexed) c.field!: i,
    };

    return [
      for (final r in validateImport(table, mapping, existing))
        ImportRow(
          rowNumber: r.rowNumber - ImportTable.rowNumberOffset + 1,
          errors: [
            ...r.errors,
            if (r.existingId != null)
              'Barcode "${_code(rows, r)}" sudah dipakai barang lain.',
          ],
          draft: r.existingId != null ? null : r.draft,
          provided: r.provided,
          stock: r.stock,
        ),
    ];
  }

  static String _code(List<BulkRowValues> rows, ImportRow r) =>
      (rows[r.rowNumber - ImportTable.rowNumberOffset][BulkColumn.code] ?? '')
          .trim();
}
