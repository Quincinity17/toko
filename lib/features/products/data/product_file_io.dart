import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../domain/product.dart';
import '../domain/product_import.dart';

class ProductFileFailure implements Exception {
  const ProductFileFailure(this.message);

  final String message;

  @override
  String toString() => 'ProductFileFailure: $message';
}

/// Format file import/export barang.
enum ProductFileFormat {
  xlsx('Excel (.xlsx)', 'xlsx'),
  csv('CSV (.csv)', 'csv');

  const ProductFileFormat(this.label, this.extension);

  final String label;
  final String extension;

  static ProductFileFormat? fromFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.xlsx')) return xlsx;
    if (lower.endsWith('.csv') || lower.endsWith('.txt')) return csv;
    return null;
  }
}

// -----------------------------------------------------------------------------
// Membaca
// -----------------------------------------------------------------------------

/// Membaca file Excel/CSV menjadi tabel teks. Dijalankan di isolate terpisah
/// karena file ribuan baris bisa butuh waktu untuk diurai.
Future<ImportTable> readProductFile(Uint8List bytes, String fileName) {
  final format = ProductFileFormat.fromFileName(fileName);
  if (format == null) {
    throw const ProductFileFailure(
      'Format file tidak didukung. Gunakan Excel (.xlsx) atau CSV (.csv). '
      'File .xls lama dari iPOS perlu disimpan ulang sebagai .xlsx.',
    );
  }
  return Isolate.run(() => parseProductFile(bytes, format));
}

/// Versi sinkron [readProductFile] (dipakai di isolate dan di tes).
ImportTable parseProductFile(Uint8List bytes, ProductFileFormat format) {
  final rows = switch (format) {
    ProductFileFormat.xlsx => _readXlsx(bytes),
    ProductFileFormat.csv => _readCsv(bytes),
  };

  // Baris judul = baris pertama yang berisi minimal 2 kolom terisi
  // (lewati judul laporan/baris kosong di atas tabel).
  final headerIndex = rows.indexWhere(
    (r) => r.where((c) => c.trim().isNotEmpty).length >= 2,
  );
  if (headerIndex == -1) {
    throw const ProductFileFailure('File kosong atau tidak berisi tabel.');
  }
  final headers = rows[headerIndex].map((h) => h.trim()).toList();
  final data = rows
      .skip(headerIndex + 1)
      .where((r) => r.any((c) => c.trim().isNotEmpty))
      .toList();
  if (data.isEmpty) {
    throw const ProductFileFailure(
      'File hanya berisi judul kolom, tanpa data.',
    );
  }
  return ImportTable(headers: headers, rows: data);
}

List<List<String>> _readXlsx(Uint8List bytes) {
  final Excel book;
  try {
    book = Excel.decodeBytes(bytes);
  } on Object {
    throw const ProductFileFailure(
      'File Excel tidak bisa dibaca. Pastikan formatnya .xlsx dan tidak rusak.',
    );
  }
  final sheetName = book.getDefaultSheet() ?? book.tables.keys.firstOrNull;
  final sheet = sheetName == null ? null : book.tables[sheetName];
  if (sheet == null) {
    throw const ProductFileFailure('File Excel tidak berisi sheet.');
  }
  return [
    for (final row in sheet.rows)
      [for (final cell in row) _cellText(cell?.value)],
  ];
}

String _cellText(CellValue? v) => switch (v) {
  null => '',
  TextCellValue() => v.value.toString(),
  IntCellValue() => '${v.value}',
  // 1500.0 → "1500"; 0.5 → "0.5" (titik desimal dipahami parseIdNumber).
  DoubleCellValue() =>
    v.value == v.value.roundToDouble() ? '${v.value.round()}' : '${v.value}',
  BoolCellValue() => v.value ? '1' : '0',
  _ => v.toString(),
};

List<List<String>> _readCsv(Uint8List bytes) {
  var text = utf8.decode(bytes, allowMalformed: true);
  if (text.startsWith('﻿')) text = text.substring(1);
  // Delimiter (, atau ;) dideteksi otomatis; ; umum di Excel versi Indonesia.
  final rows = Csv().decode(text);
  return [
    for (final r in rows) [for (final c in r) c?.toString() ?? ''],
  ];
}

// -----------------------------------------------------------------------------
// Menulis
// -----------------------------------------------------------------------------

String _qty(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

List<Object> _rowOf(Product p) => [
  p.code,
  p.barcode ?? '',
  p.name,
  p.categoryName ?? '',
  p.unitName ?? '',
  p.purchasePrice,
  p.sellingPrice,
  p.stock,
  p.minStock,
  p.isActive ? 'Ya' : 'Tidak',
  p.tags.map((t) => t.name).join(', '),
];

/// Export barang ke Excel. Judul kolom = [ProductField.label], sehingga file
/// ini bisa di-import kembali tanpa mengatur kolom.
Uint8List exportProductsXlsx(List<Product> products) =>
    exportProductsWorkbook([('Barang', products)]);

/// Export beberapa daftar barang ke satu file Excel, satu sheet per daftar
/// (mis. satu sheet per toko untuk backup). Nama sheet dirapikan sesuai
/// aturan Excel (maks. 31 huruf, tanpa `[]:*?/\`, tidak kembar).
Uint8List exportProductsWorkbook(List<(String, List<Product>)> sheets) {
  final book = Excel.createExcel();
  final used = <String>{};
  for (final (i, (title, products)) in sheets.indexed) {
    final name = _sheetName(title, used);
    final sheet = book[i == 0 ? _renameDefault(book, name) : name];
    sheet.appendRow([
      for (final f in ProductField.values) TextCellValue(f.label),
    ]);
    for (final p in products) {
      sheet.appendRow([
        for (final v in _rowOf(p))
          switch (v) {
            int() => IntCellValue(v),
            double() =>
              v == v.roundToDouble()
                  ? IntCellValue(v.round())
                  : DoubleCellValue(v),
            _ => TextCellValue('$v'),
          },
      ]);
    }
    _setWidths(sheet);
  }
  return Uint8List.fromList(book.encode()!);
}

String _sheetName(String title, Set<String> used) {
  var base = title.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  if (base.isEmpty) base = 'Sheet';
  if (base.length > 31) base = base.substring(0, 31).trim();
  var name = base;
  for (var n = 2; used.contains(name.toLowerCase()); n++) {
    final suffix = ' ($n)';
    name =
        '${base.length + suffix.length > 31 ? base.substring(0, 31 - suffix.length) : base}$suffix';
  }
  used.add(name.toLowerCase());
  return name;
}

/// Export barang ke CSV (UTF-8 dengan BOM agar terbaca benar di Excel).
Uint8List exportProductsCsv(List<Product> products) {
  final rows = [
    [for (final f in ProductField.values) f.label],
    for (final p in products)
      [for (final v in _rowOf(p)) v is double ? _qty(v) : '$v'],
  ];
  final text = Csv(addBom: true).encode(rows);
  return Uint8List.fromList(utf8.encode(text));
}

/// Template import kosong: sheet "Barang" berisi judul kolom saja, dan sheet
/// "Petunjuk" berisi penjelasan setiap kolom.
Uint8List productTemplateXlsx() {
  final book = Excel.createExcel();
  final sheet = book[_renameDefault(book, 'Barang')];
  sheet.appendRow([
    for (final f in ProductField.values) TextCellValue(f.label),
  ]);
  _setWidths(sheet);

  final help = book['Petunjuk'];
  const notes = {
    ProductField.code: 'Wajib. Kode unik barang, mis. BRG001.',
    ProductField.barcode: 'Opsional. Angka barcode tanpa spasi.',
    ProductField.name: 'Wajib. Nama barang.',
    ProductField.category: 'Opsional. Dibuat otomatis jika belum ada.',
    ProductField.unit: 'Opsional. Mis. PCS, BTL, KG. Dibuat otomatis.',
    ProductField.purchasePrice: 'Opsional. Angka tanpa "Rp", mis. 2800.',
    ProductField.sellingPrice: 'Wajib. Angka tanpa "Rp", mis. 3500.',
    ProductField.stock:
        'Opsional. Boleh desimal untuk barang timbangan, mis. 12,5.',
    ProductField.minStock: 'Opsional. Batas "stok menipis".',
    ProductField.isActive: 'Opsional. "Tidak" untuk menyembunyikan dari kasir.',
    ProductField.tags:
        'Opsional. Beberapa tag dipisah koma, mis. "Mainan, Boneka". '
        'Tag baru dibuat otomatis.',
  };
  help.appendRow([TextCellValue('Kolom'), TextCellValue('Keterangan')]);
  for (final f in ProductField.values) {
    help.appendRow([TextCellValue(f.label), TextCellValue(notes[f]!)]);
  }
  help.setColumnWidth(0, 18);
  help.setColumnWidth(1, 70);
  return Uint8List.fromList(book.encode()!);
}

/// Excel baru selalu punya "Sheet1"; ganti namanya agar rapi.
String _renameDefault(Excel book, String name) {
  final current = book.getDefaultSheet() ?? 'Sheet1';
  book.rename(current, name);
  book.setDefaultSheet(name);
  return name;
}

void _setWidths(Sheet sheet) {
  const widths = [
    12.0, 16.0, 36.0, 18.0, 10.0, 14.0, 14.0, 10.0, 14.0, 8.0, 28.0, //
  ];
  for (var i = 0; i < widths.length; i++) {
    sheet.setColumnWidth(i, widths[i]);
  }
}
