import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/products/domain/bulk_entry.dart';
import 'package:toko/features/products/domain/price_markup.dart';
import 'package:toko/features/products/domain/product_import.dart';

void main() {
  group('persen untung', () {
    test('harga jual dibulatkan ke atas ke Rp 100', () {
      expect(PriceMarkup.sellingPrice(2800, 25), 3500);
      expect(PriceMarkup.sellingPrice(2800, 20), 3400); // 3.360 → 3.400
      expect(PriceMarkup.sellingPrice(1000, 0), 1000);
      expect(PriceMarkup.sellingPrice(0, 25), isNull); // harga beli kosong
      expect(PriceMarkup.sellingPrice(1000, -5), isNull);
    });

    test('persen dari harga beli & jual, 1 desimal', () {
      expect(PriceMarkup.percent(2800, 3500), 25);
      expect(PriceMarkup.percent(3000, 3400), 13.3);
      expect(PriceMarkup.percent(0, 3500), isNull);
    });
  });

  group('Input Tabel', () {
    final none = ExistingIndex(idByCode: {}, idByBarcode: {});

    test('baris kosong dilewati, nomor baris = nomor di tabel', () {
      final rows = BulkEntry.validate([
        {},
        {
          BulkColumn.code: 'BMM0000001',
          BulkColumn.name: 'Boneka Beruang',
          BulkColumn.category: 'Mainan, Boneka',
          BulkColumn.purchasePrice: '20.000',
          BulkColumn.markup: '25',
          BulkColumn.stock: '3',
        },
        {BulkColumn.name: 'Tanpa harga'},
      ], none);
      expect(rows, hasLength(2));

      final ok = rows[0];
      expect(ok.rowNumber, 2);
      expect(ok.isValid, isTrue);
      expect(ok.draft!.sellingPrice, 25000); // dari Untung %
      expect(ok.draft!.unitName, 'PCS'); // satuan bawaan
      expect(ok.draft!.tagNames, ['Mainan', 'Boneka']);
      expect(ok.stock, 3);

      final bad = rows[1];
      expect(bad.rowNumber, 3);
      expect(
        bad.errors,
        containsAll(['Barcode kosong.', 'Harga jual kosong.']),
      );
    });

    test('barcode yang sudah ada = error (tabel hanya barang baru)', () {
      final rows = BulkEntry.validate([
        {
          BulkColumn.code: 'brg001',
          BulkColumn.name: 'Indomie',
          BulkColumn.sellingPrice: '3.500',
        },
      ], ExistingIndex(idByCode: {'brg001': 1}, idByBarcode: {}));
      expect(rows.single.isValid, isFalse);
      expect(rows.single.draft, isNull);
      expect(
        rows.single.errors.single,
        'Barcode "brg001" sudah dipakai barang lain.',
      );
    });
  });

  test('draf: hanya baris terisi, bisa dibaca lagi', () {
    final json = BulkEntry.encodeDraft([
      {BulkColumn.name: 'Boneka', BulkColumn.markup: '25', BulkColumn.unit: ''},
      {BulkColumn.name: '  '},
      {},
    ]);
    expect(BulkEntry.decodeDraft(json), [
      {BulkColumn.name: 'Boneka', BulkColumn.markup: '25'},
    ]);
    expect(BulkEntry.decodeDraft(null), isEmpty);
    expect(BulkEntry.decodeDraft('rusak'), isEmpty);
    expect(BulkEntry.decodeDraft('[{"foo": "x", "name": "A"}]'), [
      {BulkColumn.name: 'A'},
    ]);
  });
}
