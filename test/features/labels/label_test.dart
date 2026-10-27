import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/labels/data/label_pdf.dart';
import 'package:toko/features/labels/data/label_printer.dart';
import 'package:toko/features/labels/domain/label_barcode.dart';
import 'package:toko/features/receipt/data/printer_failure.dart';
import 'package:toko/features/receipt/data/receipt_settings_repository.dart';
import 'package:toko/features/receipt/domain/escpos.dart';
import 'package:toko/features/receipt/domain/printer_config.dart';
import 'package:toko/features/labels/domain/label_layout.dart';

import '../../helpers/fake_printer.dart';
import '../../helpers/test_app.dart';

void main() {
  final a4 = LabelLayout.byId('a4-3x8');
  final roll = LabelLayout.byId('roll-50x30');

  test('susunan A4 3 × 8 ada di tengah kertas', () {
    expect(a4.perPage, 24);
    expect(a4.isRoll, isFalse);
    final first = a4.origin(0);
    final last = a4.origin(23);
    expect(first.x, closeTo(7.25, 0.01));
    expect(first.y, closeTo((297 - 8 * 33.9) / 2, 0.01));
    // Kanan bawah: margin kanan = margin kiri.
    expect(210 - (last.x + a4.labelWidth), closeTo(first.x, 0.01));
    // Slot 3 = baris kedua, kolom pertama.
    expect(a4.origin(3).x, first.x);
    expect(a4.origin(3).y, closeTo(first.y + 33.9, 0.01));
  });

  test('jumlah halaman memperhitungkan label pertama yang dilewati', () {
    expect(labelPageCount(a4, 0), 0);
    expect(labelPageCount(a4, 24), 1);
    expect(labelPageCount(a4, 25), 2);
    expect(labelPageCount(a4, 20, startAt: 5), 1);
    expect(labelPageCount(a4, 21, startAt: 5), 2);
    expect(labelPageCount(roll, 3, startAt: 9), 3);
  });

  test('preset tidak dikenal = preset pertama', () {
    expect(LabelLayout.byId('tidak-ada').id, LabelLayout.presets.first.id);
  });

  test('PDF label: satu halaman per label rol, barcode Code 128', () async {
    final bytes = await buildLabelPdf(
      items: const [
        LabelItem(
          productId: 1,
          name: 'Indomie Goreng',
          code: 'BRG001',
          price: 3500,
          copies: 2,
        ),
        LabelItem(
          productId: 1,
          unitId: 7,
          name: 'Indomie Goreng',
          code: '8991002101234',
          price: 80000,
          unitName: 'DUS',
        ),
      ],
      layout: roll,
      options: const LabelOptions(storeName: 'Toko Utama'),
    );
    final text = latin1.decode(bytes);
    expect(text, startsWith('%PDF'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text), hasLength(3));
  });

  test('PDF label A4: 30 label = 2 halaman', () async {
    final bytes = await buildLabelPdf(
      items: const [
        LabelItem(productId: 1, name: 'A', code: 'A1', price: 1, copies: 30),
      ],
      layout: a4,
    );
    final text = latin1.decode(bytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text), hasLength(2));
  });

  test('barcode pabrik: EAN-13 sah dipakai bila dipilih', () {
    expect(labelSymbology('8991002101234'), isNotNull);
    expect(labelSymbology('8991002101234')!.name, contains('EAN 13'));
    expect(labelSymbology('BMM0000001')!.name, contains('CODE 128'));
    // Digit pemeriksa salah → Code 128.
    expect(labelSymbology('8991002101235')!.name, contains('CODE 128'));
    const item = LabelItem(
      productId: 1,
      name: 'Indomie',
      code: 'BRG001',
      factoryCode: '8991002101234',
      price: 3500,
    );
    expect(const LabelOptions().codeOf(item), 'BRG001');
    expect(
      const LabelOptions(useFactoryBarcode: true).codeOf(item),
      '8991002101234',
    );
  });

  test('cetak langsung ke printer nota: satu gambar per barang, sebanyak '
      'jumlah label', () async {
    final db = await createSeededDb();
    addTearDown(db.close);
    final admin = await AuthRepository(
      db,
      testHasher,
    ).login('admin', 'admin123');
    final settings = ReceiptSettingsRepository(db);
    final transport = FakeTransport();
    final widths = <double>[];
    final printer = LabelPrinter(
      settings,
      transport,
      rasterize: (widget, width) async {
        widths.add(width);
        return MonoBitmap(width.round(), 10)..setBlack(0, 0);
      },
    );
    const items = [
      LabelItem(productId: 1, name: 'A', code: 'A1', price: 1000, copies: 3),
      LabelItem(productId: 2, name: 'B', code: 'B1', price: 2000),
    ];
    await expectLater(
      printer.print(items, roll, const LabelOptions()),
      throwsA(isA<PrinterFailure>()),
    );
    await settings.savePrinter(
      admin,
      const PrinterConfig(
        connection: PrinterConnection.system,
        printerName: 'Thermal 58',
      ),
    );
    await printer.print(items, roll, const LabelOptions());
    // 50 mm × 8 titik/mm = 400 > kertas 58 mm (384 titik) → diperkecil.
    expect(widths, [384, 384]);
    final job = transport.jobs.single;
    // 4 gambar raster (GS v 0).
    var rasters = 0;
    for (var i = 0; i + 2 < job.length; i++) {
      if (job[i] == 0x1d && job[i + 1] == 0x76 && job[i + 2] == 0x30) {
        rasters++;
      }
    }
    expect(rasters, 4);
  });
}
