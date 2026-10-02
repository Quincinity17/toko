import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/receipt/data/printer_failure.dart';
import 'package:toko/features/receipt/data/receipt_printer.dart';
import 'package:toko/features/receipt/data/receipt_settings_repository.dart';
import 'package:toko/features/receipt/domain/default_receipt_html.dart';
import 'package:toko/features/receipt/domain/escpos.dart';
import 'package:toko/features/receipt/domain/printer_config.dart';
import 'package:toko/features/receipt/domain/receipt.dart';
import 'package:toko/features/receipt/domain/receipt_html.dart';
import 'package:toko/features/receipt/domain/receipt_template.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/stores/data/store_repository.dart';

import '../../helpers/fake_printer.dart';
import '../../helpers/test_app.dart';

const drawerPin2 = [0x1B, 0x70, 0, 25, 250];
const cutCmd = [0x1D, 0x56, 66, 0];

bool containsSeq(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length && ok; j++) {
      ok = haystack[i + j] == needle[j];
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  group('ReceiptHtml', () {
    final sample = ReceiptData.sample(storeName: 'Toko <Maju> & Jaya');

    test('variabel, perulangan barang, dan escape HTML', () {
      final html = ReceiptHtml.render(
        '<b>{{toko.nama}}</b>{{#barang}}<p>{{no}}. {{nama}} {{qty}} x '
        '{{harga}} = {{total}}</p>{{/barang}}<i>{{total}}</i>',
        sample.toTemplateValues(),
      );
      expect(html, contains('Toko &lt;Maju&gt; &amp; Jaya'));
      expect(
        html,
        contains('<p>3. Gula Pasir Gulaku 1 kg 1,5 x 17.000 = 25.500</p>'),
      );
      expect(html, contains('<i>51.000</i>'));
    });

    test('bagian bersyarat: kembali, ref, cetak ulang, kebalikan', () {
      const tpl =
          '{{#kembali}}K{{kembali}}{{/kembali}}{{#ref}}R{{ref}}{{/ref}}'
          '{{#cetak_ulang}}ULANG{{/cetak_ulang}}{{^potongan}}TANPA{{/potongan}}';
      expect(
        ReceiptHtml.render(tpl, sample.toTemplateValues()),
        contains('K49.000'),
      );
      final qris = ReceiptData(
        storeName: 'A',
        invoiceNo: 'X',
        date: DateTime(2026),
        cashierName: 'B',
        items: const [],
        subtotal: 1000,
        total: 1000,
        paid: 1000,
        change: 0,
        paymentMethod: 'QRIS',
        isCash: false,
        paymentRef: ' QR-1 ',
      );
      final out = ReceiptHtml.render(tpl, qris.toTemplateValues(reprint: true));
      expect(out, isNot(contains('K')));
      expect(out, contains('RQR-1'));
      expect(out, contains('ULANG'));
      expect(out, contains('TANPA'));
    });

    test('template rusak memberi pesan yang jelas', () {
      expect(
        () => ReceiptHtml.render('<p>\n{{#barang}}\n<p>', {}),
        throwsA(
          isA<ReceiptTemplateError>().having(
            (e) => e.message,
            'message',
            contains('belum ditutup'),
          ),
        ),
      );
    });

    test('CSS <style> ditempel ke elemen; inline paling kuat', () {
      final html = ReceiptHtml.inlineCss('''
<style>
  /* komentar */
  body { font-size: 20px }
  .a, #b { color: red; }
  div p { margin: 0 }
  @media print { .a { color: blue } }
  .a { font-weight: bold }
</style>
<div><p class="a" style="color: green">x</p><span id="b">y</span></div>''');
      expect(html, startsWith('<div style="font-size: 20px">'));
      expect(
        html,
        contains(
          'style="color: red; margin: 0; font-weight: bold; color: green"',
        ),
      );
      expect(html, contains('<span id="b" style="color: red">'));
      expect(html, isNot(contains('<style')));
      expect(html, isNot(contains('blue')));
    });

    test('anak flex dijadikan block; garis kosong tetap digambar', () {
      final html = ReceiptHtml.inlineCss(
        '<style>.r{display:flex}.g{border-top:1px solid #000}</style>'
        '<div class="r"><span>A</span><span style="color:red">B</span></div>'
        '<div class="g"></div><img src="x">',
      );
      expect(html, contains('<span style="display: block">A</span>'));
      expect(
        html,
        contains('<span style="display: block; color:red">B</span>'),
      );
      expect(html, contains('​'));
    });

    test('template bawaan terisi lengkap tanpa error', () {
      final html = ReceiptHtml.render(
        defaultReceiptHtml,
        sample.toTemplateValues(logo: 'data:image/png;base64,AAAA'),
      );
      expect(html, contains('INV-K01-20261002-0001'));
      expect(html, contains('base64,AAAA'));
      expect(html, isNot(contains('{{')));
    });
  });

  group('EscPos', () {
    test('RGBA ke 1 bit: gelap = hitam, transparan = putih', () {
      final rgba = Uint8List(9 * 2 * 4);
      void px(int x, int y, int v, [int a = 255]) {
        final i = (y * 9 + x) * 4;
        rgba
          ..[i] = v
          ..[i + 1] = v
          ..[i + 2] = v
          ..[i + 3] = a;
      }

      for (var x = 0; x < 9; x++) {
        px(x, 0, 255);
        px(x, 1, 255);
      }
      px(0, 0, 0);
      px(1, 0, 200);
      px(2, 0, 100);
      px(3, 0, 0, 0);
      px(8, 0, 0);
      final bmp = MonoBitmap.fromRgba(rgba, 9, 2);
      expect(bmp.widthBytes, 2);
      expect(
        [for (var x = 0; x < 9; x++) bmp.isBlack(x, 0)],
        [true, false, true, false, false, false, false, false, true],
      );
      expect(bmp.bytes.sublist(0, 2), [0xA0, 0x80]);
      expect(bmp.trimBottom().height, 1);
    });

    test('raster dipotong per 128 baris; laci di awal, potong di akhir', () {
      final bmp = MonoBitmap(16, 200);
      final bytes = buildReceiptJob(bmp, openDrawer: true);
      expect(bytes.sublist(0, 2), [0x1B, 0x40]);
      expect(bytes.sublist(2, 7), drawerPin2);
      // GS v 0, lebar 2 byte, tinggi 128 lalu 72.
      expect(bytes.sublist(7, 15), [0x1D, 0x76, 0x30, 0, 2, 0, 128, 0]);
      const second = 15 + 2 * 128;
      expect(bytes.sublist(second, second + 8), [
        0x1D,
        0x76,
        0x30,
        0,
        2,
        0,
        72,
        0,
      ]);
      expect(bytes.sublist(bytes.length - 4), cutCmd);
      expect(containsSeq(buildReceiptJob(bmp, cut: false), cutCmd), isFalse);
      expect(buildDrawerKick(pin: 5).sublist(2), [0x1B, 0x70, 1, 25, 250]);
    });
  });

  group('pengaturan', () {
    test('JSON bolak-balik dan nilai rusak memakai default', () {
      const t = ReceiptTemplate(
        html: '<p>{{total}}</p>',
        logo: 'data:image/png;base64,AAAA',
      );
      expect(ReceiptTemplate.fromJson(t.toJson()), t);
      final broken = ReceiptTemplate.fromJson({
        'html': '  ',
        'logo': 'http://contoh/logo.png',
      });
      expect(broken, const ReceiptTemplate());

      const p = PrinterConfig(
        connection: PrinterConnection.network,
        paperWidth: PaperWidth.mm80,
        host: '192.168.1.50',
        drawerPin: 5,
        autoPrint: false,
        feedLines: 6,
      );
      expect(PrinterConfig.fromJson(p.toJson()), p);
      expect(PrinterConfig.fromJson({'port': -1}).port, 9100);
      expect(PrinterConfig.fromJson({'feedLines': 99}).feedLines, 8);
      expect(
        PrinterConfig.fromJson({'paperWidth': 'mm99'}).paperWidth,
        PaperWidth.mm58,
      );

      const bt = PrinterConfig(
        connection: PrinterConnection.serial,
        serialPort: 'COM5',
        baudRate: 115200,
      );
      expect(PrinterConfig.fromJson(bt.toJson()), bt);
      expect(bt.isReady, isTrue);
      expect(bt.summary, 'COM5 · 115200');
      expect(PrinterConfig.fromJson({'baudRate': 1234}).baudRate, 9600);
      expect(
        const PrinterConfig(connection: PrinterConnection.serial).isReady,
        isFalse,
      );
    });
  });

  group('ReceiptPrinter', () {
    late AppDatabase db;
    late AppUser admin;
    late AppUser kasir;
    late FakeTransport transport;
    late FakeRasterizer rasterizer;
    late ReceiptSettingsRepository settings;
    late ReceiptPrinter printer;
    late int storeA;

    setUp(() async {
      db = await createSeededDb();
      final auth = AuthRepository(db, testHasher);
      admin = await auth.login('admin', 'admin123');
      kasir = await auth.login('kasir', 'kasir123');
      transport = FakeTransport();
      rasterizer = FakeRasterizer();
      settings = ReceiptSettingsRepository(db);
      printer = ReceiptPrinter(db, settings, transport, rasterizer);
      storeA = await mainStoreId(db);
    });

    tearDown(() => db.close());

    Future<CheckoutResult> sell(String method, {int? storeId}) async {
      final store = storeId ?? storeA;
      final product = await ProductRepository(db)
          .findByCodeOrBarcode('BRG001', storeId: store);
      final pm = (await db.paymentMethodsDao.findByName(method))!;
      return CheckoutService(db).checkout(
        cart: const Cart().add(product!, qty: 2),
        cashier: kasir,
        storeId: store,
        paymentMethodId: pm.id,
        paid: 100000,
        paymentRef: method == 'Tunai' ? null : 'REF-9',
      );
    }

    Future<void> configure({bool autoPrint = true}) => settings.savePrinter(
      admin,
      PrinterConfig(
        connection: PrinterConnection.system,
        printerName: 'Thermal 58',
        autoPrint: autoPrint,
      ),
    );

    test('bentuk struk hanya admin; printer boleh diatur kasir', () async {
      expect(
        () => settings.saveTemplate(
          kasir,
          const ReceiptTemplate(),
          storeId: storeA,
        ),
        throwsA(isA<PrinterFailure>()),
      );
      expect(await settings.templateFor(storeA), const ReceiptTemplate());
      await settings.saveTemplate(
        admin,
        const ReceiptTemplate(html: '<p>hai</p>'),
        storeId: storeA,
      );
      expect((await settings.templateFor(storeA)).html, '<p>hai</p>');

      await settings.savePrinter(
        kasir,
        const PrinterConfig(paperWidth: PaperWidth.mm80),
      );
      expect((await settings.printer()).paperWidth, PaperWidth.mm80);
    });

    test('template & logo per toko; "semua toko" hanya menyalin HTML, '
        'logo tiap toko tetap', () async {
      final storeB = (await StoreRepository(
        db,
      ).save(actor: admin, name: 'Toko B')).id;
      const logoA = 'data:image/png;base64,AAAA';
      const logoB = 'data:image/png;base64,BBBB';
      await settings.saveTemplate(
        admin,
        const ReceiptTemplate(html: 'A', logo: logoA),
        storeId: storeA,
      );
      await settings.saveTemplate(
        admin,
        const ReceiptTemplate(html: 'B', logo: logoB),
        storeId: storeB,
      );
      expect(
        await settings.templateFor(storeA),
        const ReceiptTemplate(html: 'A', logo: logoA),
      );
      expect(
        await settings.templateFor(storeB),
        const ReceiptTemplate(html: 'B', logo: logoB),
      );

      expect(
        () => settings.applyHtmlToAllStores(kasir, 'X'),
        throwsA(isA<PrinterFailure>()),
      );
      await settings.applyHtmlToAllStores(admin, 'SEMUA');
      expect(
        await settings.templateFor(storeA),
        const ReceiptTemplate(html: 'SEMUA', logo: logoA),
      );
      expect(
        await settings.templateFor(storeB),
        const ReceiptTemplate(html: 'SEMUA', logo: logoB),
      );
    });

    test('belum diatur: tidak mencetak apa pun', () async {
      final r = await sell('Tunai');
      expect(
        await printer.afterCheckout(r.saleId, isCash: r.isCash),
        AfterCheckout.nothing,
      );
      expect(transport.jobs, isEmpty);
      expect(rasterizer.html, isEmpty);
    });

    test('tunai: struk dari template + laci; non-tunai tanpa laci', () async {
      await configure();
      await settings.saveTemplate(
        admin,
        storeId: storeA,
        const ReceiptTemplate(
          html:
              '<p>{{toko.nama}}|{{faktur.no}}|{{kasir}}|{{metode}}'
              '{{#tunai}}|TUNAI{{/tunai}}{{#ref}}|{{ref}}{{/ref}}'
              '{{#cetak_ulang}}|ULANG{{/cetak_ulang}}</p>',
        ),
      );

      final cash = await sell('Tunai');
      expect(cash.isCash, isTrue);
      expect(
        await printer.afterCheckout(cash.saleId, isCash: true),
        AfterCheckout.printed,
      );
      expect(containsSeq(transport.jobs.single, drawerPin2), isTrue);
      expect(
        rasterizer.html.single,
        contains(
          'Toko Utama|${cash.invoiceNo}|${kasir.fullName}|Tunai|TUNAI</p>',
        ),
      );

      final qris = await sell('QRIS');
      await printer.afterCheckout(qris.saleId, isCash: false);
      expect(containsSeq(transport.jobs.last, drawerPin2), isFalse);
      expect(rasterizer.html.last, contains('|QRIS|REF-9</p>'));

      await printer.printSale(qris.saleId, reprint: true);
      expect(rasterizer.html.last, contains('|ULANG'));
    });

    test('struk mengikuti toko faktur dan lebar kertas printer', () async {
      await settings.savePrinter(
        admin,
        const PrinterConfig(
          connection: PrinterConnection.system,
          printerName: 'Thermal 80',
          paperWidth: PaperWidth.mm80,
        ),
      );
      final storeB = (await StoreRepository(
        db,
      ).save(actor: admin, name: 'Toko B', address: 'Jl. B')).id;
      await settings.saveTemplate(
        admin,
        const ReceiptTemplate(html: '<p>Struk B {{toko.nama}}</p>'),
        storeId: storeB,
      );
      // Admin boleh berjualan di toko mana pun.
      final store = await mainStoreId(db);
      final product = await ProductRepository(db)
          .findByCodeOrBarcode('BRG001', storeId: store);
      final pm = (await db.paymentMethodsDao.findByName('Tunai'))!;
      final sale = await CheckoutService(db).checkout(
        cart: const Cart().add(product!, qty: 1),
        cashier: admin,
        storeId: storeB,
        paymentMethodId: pm.id,
        paid: 100000,
      );
      await printer.printSale(sale.saleId);
      expect(rasterizer.html.single, contains('Struk B Toko B'));
      expect(rasterizer.widths.single, PaperWidth.mm80);

      // Toko A tetap memakai template bawaan.
      final a = await sell('Tunai');
      await printer.printSale(a.saleId);
      expect(rasterizer.html.last, contains('INV-'));
      expect(rasterizer.html.last, isNot(contains('Struk B')));
    });

    test('cetak otomatis mati: tunai hanya membuka laci', () async {
      await configure(autoPrint: false);
      final r = await sell('Tunai');
      expect(
        await printer.afterCheckout(r.saleId, isCash: true),
        AfterCheckout.drawerOpened,
      );
      expect(transport.jobs.single, buildDrawerKick());
      expect(rasterizer.html, isEmpty);
    });

    test('template rusak: gagal cetak dengan pesan jelas', () async {
      await configure();
      await settings.saveTemplate(
        admin,
        const ReceiptTemplate(html: '{{#barang}}<p>'),
        storeId: storeA,
      );
      final r = await sell('Tunai');
      expect(
        () => printer.printSale(r.saleId),
        throwsA(
          isA<PrinterFailure>().having(
            (e) => e.message,
            'message',
            startsWith('Template struk salah.'),
          ),
        ),
      );
    });

    test('buka laci manual gagal jika printer belum diatur', () async {
      expect(printer.openDrawer(), throwsA(isA<PrinterFailure>()));
    });
  });
}
