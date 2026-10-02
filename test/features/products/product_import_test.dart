import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/database/tables/sales.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/products/data/product_file_io.dart';
import 'package:toko/features/products/data/product_import_service.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/products/domain/product_import.dart';

import '../../helpers/test_app.dart';

Uint8List csvBytes(String text) => Uint8List.fromList(utf8.encode(text));

void main() {
  group('tebakan kolom', () {
    test('judul kolom gaya iPOS', () {
      final m = guessMapping([
        'No',
        'Kode Item',
        'Barcode',
        'Nama Item',
        'Jenis',
        'Satuan',
        'Harga Pokok',
        'Harga Jual 1',
        'Stok',
        'Stok Min',
      ]);
      expect(m[ProductField.code], 1);
      expect(m[ProductField.barcode], 2);
      expect(m[ProductField.name], 3);
      expect(m[ProductField.category], 4);
      expect(m[ProductField.unit], 5);
      expect(m[ProductField.purchasePrice], 6);
      expect(m[ProductField.sellingPrice], 7);
      expect(m[ProductField.stock], 8);
      expect(m[ProductField.minStock], 9);
    });

    test('judul hasil export aplikasi ini', () {
      final m = guessMapping([for (final f in ProductField.values) f.label]);
      for (final (i, f) in ProductField.values.indexed) {
        expect(m[f], i, reason: f.label);
      }
    });

    test('kolom tidak dikenal dibiarkan kosong', () {
      final m = guessMapping(['Foo', 'Nama Barang', 'Bar']);
      expect(m[ProductField.name], 1);
      expect(m[ProductField.code], isNull);
    });
  });

  group('validasi', () {
    final empty = ExistingIndex(idByCode: {}, idByBarcode: {});

    List<ImportRow> check(String csv, {ExistingIndex? existing}) {
      final table = parseProductFile(csvBytes(csv), ProductFileFormat.csv);
      return validateImport(
        table,
        guessMapping(table.headers),
        existing ?? empty,
      );
    }

    test('baris error: harga kosong, angka salah, kode duplikat', () {
      final rows = check(
        'Kode,Nama,Harga Jual,Stok\n'
        'A1,Gula,17500,10\n'
        'A2,Garam,,5\n'
        'A3,Teh,abc,1\n'
        'A1,Gula Lagi,18000,2\n'
        ',Tanpa Kode,1000,0\n',
      );
      expect(rows.map((r) => r.isValid), [true, false, false, false, false]);
      expect(rows[1].errors.single, 'Harga jual kosong.');
      expect(rows[2].errors.single, contains('bukan angka'));
      expect(rows[3].errors.single, contains('duplikat dengan baris 2'));
      expect(rows[4].errors.single, 'Kode kosong.');
      expect(rows.map((r) => r.rowNumber), [2, 3, 4, 5, 6]);
    });

    test('format angka Indonesia dan desimal', () {
      final rows = check(
        'Kode;Nama;Harga Beli;Harga Jual;Stok\n'
        'T1;Telur;"26.000";"29.000,00";"12,5"\n',
      );
      final d = rows.single.draft!;
      expect(d.purchasePrice, 26000);
      expect(d.sellingPrice, 29000);
      expect(rows.single.stock, 12.5);
    });

    test('kode yang sudah ada ditandai, barcode milik barang lain error', () {
      final existing = ExistingIndex(
        idByCode: {'brg001': 1},
        idByBarcode: {'8991234000015': 1},
      );
      final rows = check(
        'Kode,Nama,Barcode,Harga Jual\n'
        'BRG001,Indomie,8991234000015,3600\n'
        'BARU1,Lain,8991234000015,1000\n',
        existing: existing,
      );
      expect(rows[0].isExisting, isTrue);
      expect(rows[1].errors, [
        contains('duplikat dengan baris 2'),
        contains('sudah dipakai barang lain'),
      ]);
    });
  });

  group('file', () {
    final products = [
      const Product(
        id: 1,
        code: 'BRG001',
        barcode: '8991234000015',
        name: 'Indomie, "Goreng" 85g',
        categoryName: 'Makanan',
        unitName: 'PCS',
        purchasePrice: 2800,
        sellingPrice: 3500,
        stock: 120,
        minStock: 24,
      ),
      const Product(
        id: 2,
        code: 'BRG008',
        name: 'Telur Ayam',
        unitName: 'KG',
        purchasePrice: 26000,
        sellingPrice: 29000,
        stock: 12.5,
        minStock: 5,
        isActive: false,
      ),
    ];

    for (final format in ProductFileFormat.values) {
      test('export ${format.extension} bisa di-import kembali', () {
        final bytes = format == ProductFileFormat.xlsx
            ? exportProductsXlsx(products)
            : exportProductsCsv(products);
        final table = parseProductFile(bytes, format);
        final rows = validateImport(
          table,
          guessMapping(table.headers),
          ExistingIndex(idByCode: {}, idByBarcode: {}),
        );
        expect(rows.every((r) => r.isValid), isTrue);
        final a = rows[0].draft!, b = rows[1].draft!;
        expect(a.name, 'Indomie, "Goreng" 85g');
        expect(a.barcode, '8991234000015');
        expect(a.categoryName, 'Makanan');
        expect(a.sellingPrice, 3500);
        expect(rows[1].stock, 12.5);
        expect(b.barcode, isNull);
        expect(b.isActive, isFalse);
      });
    }

    test('template berisi judul kolom dan petunjuk', () {
      final book = Excel.decodeBytes(productTemplateXlsx());
      expect(book.tables.keys, containsAll(['Barang', 'Petunjuk']));
      final headers = book.tables['Barang']!.rows.first
          .map((c) => c?.value.toString())
          .toList();
      expect(headers, [for (final f in ProductField.values) f.label]);
    });

    test('baris judul laporan di atas tabel dilewati', () {
      final table = parseProductFile(
        csvBytes(
          'Daftar Barang Toko\n'
          '\n'
          'Kode,Nama,Harga Jual\n'
          'A1,Gula,17500\n',
        ),
        ProductFileFormat.csv,
      );
      expect(table.headers, ['Kode', 'Nama', 'Harga Jual']);
      expect(table.rows, hasLength(1));
    });

    test('format tidak didukung ditolak', () {
      expect(
        () => readProductFile(Uint8List(0), 'barang.xls'),
        throwsA(isA<ProductFileFailure>()),
      );
    });
  });

  group('jalankan import', () {
    late AppDatabase db;
    late ProductImportService service;
    late AppUser admin;

    setUp(() async {
      db = await createSeededDb();
      service = ProductImportService(db);
      admin = await AuthRepository(db, testHasher).login('admin', 'admin123');
    });

    tearDown(() => db.close());

    Future<List<ImportRow>> rowsOf(String csv) async {
      final table = parseProductFile(csvBytes(csv), ProductFileFormat.csv);
      return validateImport(
        table,
        guessMapping(table.headers),
        await service.existingIndex(),
      );
    }

    const file =
        'Kode,Nama,Kategori,Satuan,Harga Beli,Harga Jual,Stok\n'
        'BRG001,Indomie Goreng Baru,Mie Instan,pcs,2900,3700,150\n'
        'BRG500,Kecap Bango,Bumbu,BTL,9000,11000,12\n'
        'BRG501,Saus ABC,Bumbu,BTL,7000,,3\n';

    test(
      'barang baru dibuat, kategori/satuan baru otomatis, error dilewati',
      () async {
        final rows = await rowsOf(file);
        final progress = <int>[];
        final result = await service.run(
          actor: admin,
          rows: rows,
          existingAction: ExistingProductAction.skip,
          stockStoreId: await mainStoreId(db),
          onProgress: (done, _) => progress.add(done),
        );
        expect(result.inserted, 1);
        expect(result.skipped, 1);
        expect(result.failed.single.rowNumber, 4);
        expect(result.newCategories, 1); // Bumbu
        expect(result.newUnits, 0); // BTL sudah ada
        expect(progress.last, 2);

        final repo = ProductRepository(db);
        final kecap = (await repo.findByCodeOrBarcode('BRG500'))!;
        expect(kecap.categoryName, 'Bumbu');
        final indomie = (await repo.findByCodeOrBarcode('BRG001'))!;
        expect(indomie.name, 'Indomie Goreng 85g'); // dilewati, tidak berubah
        final moves = await (db.select(
          db.stockMovements,
        )..where((m) => m.productId.equals(kecap.id))).get();
        expect(moves.single.type, StockMovementType.import);
      },
    );

    test('timpa semua data', () async {
      await service.run(
        actor: admin,
        rows: await rowsOf(file),
        existingAction: ExistingProductAction.overwrite,
        stockStoreId: await mainStoreId(db),
      );
      final p = (await ProductRepository(db).findByCodeOrBarcode('BRG001'))!;
      expect(p.name, 'Indomie Goreng Baru');
      expect(p.categoryName, 'Mie Instan');
      expect(p.sellingPrice, 3700);
      expect(p.stock, 150);
      expect(p.barcode, '8991234000015'); // tidak ada di file → tetap
    });

    test('update stok & harga saja', () async {
      final result = await service.run(
        actor: admin,
        rows: await rowsOf(file),
        existingAction: ExistingProductAction.updateStockPrice,
        stockStoreId: await mainStoreId(db),
      );
      expect(result.updated, 1);
      final p = (await ProductRepository(db).findByCodeOrBarcode('BRG001'))!;
      expect(p.name, 'Indomie Goreng 85g'); // nama tetap
      expect(p.categoryName, 'Makanan'); // kategori tetap
      expect(p.purchasePrice, 2900);
      expect(p.sellingPrice, 3700);
      expect(p.stock, 150);
      final moves = await (db.select(
        db.stockMovements,
      )..where((m) => m.productId.equals(p.id))).get();
      expect(moves.single.qtyChange, 30); // 120 → 150
    });

    test('ribuan baris dalam satu transaksi', () async {
      final buffer = StringBuffer('Kode,Nama,Harga Jual,Stok\n');
      for (var i = 0; i < 3000; i++) {
        buffer.writeln('X$i,Barang $i,${1000 + i},$i');
      }
      final sw = Stopwatch()..start();
      final result = await service.run(
        actor: admin,
        rows: await rowsOf(buffer.toString()),
        existingAction: ExistingProductAction.skip,
        stockStoreId: await mainStoreId(db),
      );
      sw.stop();
      expect(result.inserted, 3000);
      expect(
        await ProductRepository(db)
            .watchCount(const ProductFilter(status: ProductStatusFilter.all))
            .first,
        3020,
      );
      // ignore: avoid_print
      print('Import 3000 baris: ${sw.elapsedMilliseconds} ms');
    });
  });
}
