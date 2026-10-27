import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/audit/data/integrity_service.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/payments/domain/payment_method.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/products/domain/product_pricing.dart';
import 'package:toko/features/stores/data/store_repository.dart';
import 'package:toko/features/receipt/data/receipt_printer.dart';
import 'package:toko/features/receipt/data/receipt_settings_repository.dart';
import 'package:toko/features/receipt/domain/printer_config.dart';
import 'package:toko/features/reports/data/report_repository.dart';
import 'package:toko/features/reports/domain/report_models.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/data/held_cart_repository.dart';
import 'package:toko/features/sales/data/return_service.dart';
import 'package:toko/features/sales/data/sales_repository.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/sales/domain/day_total.dart';
import 'package:toko/features/sales/domain/split_payment.dart';

import '../../helpers/fake_printer.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late ProductRepository products;
  late AppUser kasir;
  late AppUser admin;
  late int store;
  late PaymentMethod tunai;
  late PaymentMethod qris;
  final saleAt = DateTime(2026, 10, 16, 9);

  setUpAll(() => initializeDateFormatting('id_ID'));

  setUp(() async {
    db = await createSeededDb();
    products = ProductRepository(db);
    final auth = AuthRepository(db, testHasher);
    kasir = await auth.login('kasir', 'kasir123');
    admin = await auth.login('admin', 'admin123');
    store = await mainStoreId(db);
    final methods = await PaymentMethodRepository(db).watchAll().first;
    tunai = methods.firstWhere((m) => m.name == 'Tunai');
    qris = methods.firstWhere((m) => m.name == 'QRIS');
  });
  tearDown(() => db.close());

  /// Indomie (BRG001, 3.500/PCS, beli 2.800) + DUS isi 24 berbarcode +
  /// grosir min. 10 = 3.300.
  Future<Product> withPricing() async {
    final p = (await products.findByCodeOrBarcode('BRG001'))!;
    return products.save(
      actor: admin,
      id: p.id,
      draft: ProductDraft(
        code: p.code,
        barcode: p.barcode,
        name: p.name,
        unitName: p.unitName,
        purchasePrice: p.purchasePrice,
        sellingPrice: p.defaultSellingPrice,
        units: const [
          ProductUnit(
            name: 'dus',
            factor: 24,
            price: 78000,
            barcode: 'DUS-IDM',
          ),
        ],
        tiers: const [PriceTier(minQty: 10, price: 3300)],
      ),
    );
  }

  Future<double> stock(Product p) async =>
      (await products.findByCodeOrBarcode(p.code, storeId: store))!.stock;

  CheckoutService checkout() => CheckoutService(db, clock: () => saleAt);

  group('Multi-satuan & grosir', () {
    test(
      'disimpan, dimuat, dan dicatat; barcode kemasan bisa di-scan',
      () async {
        final p = await withPricing();
        expect(p.units.single.name, 'DUS');
        expect(p.units.single.factor, 24);
        expect(p.tiers.single.price, 3300);

        final match = (await products.scan('DUS-IDM', storeId: store))!;
        expect(match.product.id, p.id);
        expect(match.unit?.name, 'DUS');
        expect((await products.scan('BRG001'))!.unit, isNull);
        expect(await products.scan('TIDAK-ADA'), isNull);

        final log = await db.select(db.auditLog).get();
        expect(
          log.last.summary,
          allOf(contains('satuan lain'), contains('harga grosir')),
        );

        // Mengubah tanpa menyentuh satuan (`units: null`) = tetap.
        await products.save(
          actor: admin,
          id: p.id,
          draft: ProductDraft(
            code: p.code,
            barcode: p.barcode,
            name: 'Indomie Goreng Baru',
            unitName: p.unitName,
            purchasePrice: p.purchasePrice,
            sellingPrice: p.defaultSellingPrice,
          ),
        );
        final again = (await products.findByCodeOrBarcode('BRG001'))!;
        expect(again.units.single.id, p.units.single.id);
        expect(again.tiers, hasLength(1));
      },
    );

    test('barcode kemasan tidak boleh bentrok dengan barang lain', () async {
      await withPricing();
      final aqua = (await products.findByCodeOrBarcode('BRG009'))!;
      ProductDraft draft({String? code, List<ProductUnit>? units}) =>
          ProductDraft(
            code: code ?? aqua.code,
            name: aqua.name,
            sellingPrice: aqua.defaultSellingPrice,
            units: units,
          );
      // Kode barang lain = barcode kemasan Indomie.
      await expectLater(
        products.save(
          actor: admin,
          id: aqua.id,
          draft: draft(code: 'DUS-IDM'),
        ),
        throwsA(
          isA<ProductFailure>().having(
            (e) => e.message,
            'message',
            contains('satuan DUS'),
          ),
        ),
      );
      // Barcode kemasan = kode barang lain.
      await expectLater(
        products.save(
          actor: admin,
          id: aqua.id,
          draft: draft(
            units: const [
              ProductUnit(name: 'DUS', factor: 12, price: 1, barcode: 'BRG001'),
            ],
          ),
        ),
        throwsA(isA<ProductFailure>()),
      );
      // Harga grosir tidak lebih murah = ditolak.
      await expectLater(
        products.save(
          actor: admin,
          id: aqua.id,
          draft: ProductDraft(
            code: aqua.code,
            name: aqua.name,
            sellingPrice: aqua.defaultSellingPrice,
            tiers: [PriceTier(minQty: 6, price: aqua.defaultSellingPrice)],
          ),
        ),
        throwsA(isA<ProductFailure>()),
      );
    });

    test('jual DUS: stok berkurang 24/DUS, harga beli per DUS; retur '
        'mengembalikan stok sesuai isi', () async {
      final p = await withPricing();
      final before = await stock(p);
      final result = await checkout().checkout(
        cart: const Cart().add(p, qty: 2, unit: p.units.single),
        cashier: kasir,
        storeId: store,
        paymentMethodId: tunai.id,
        paid: 200000,
      );
      expect(result.total, 156000);
      expect(await stock(p), before - 48);
      final item = (await db.salesDao.itemsOf(result.saleId)).single;
      expect(item.unitName, 'DUS');
      expect(item.unitFactor, 24);
      expect(item.qty, 2);
      expect(item.purchasePrice, 2800 * 24);

      // Laporan: qty dalam satuan dasar, laba benar.
      final report = ReportRepository(db, storeId: store);
      final range = ReportRange(saleAt, saleAt.add(const Duration(days: 1)));
      final top = (await report.bundle(range)).products.single;
      expect(top.quantity, 48);
      expect(top.revenue, 156000);
      expect(top.cost, 2 * 24 * 2800);

      final ret = ReturnService(db, clock: () => saleAt);
      await ret.create(
        actor: admin,
        saleId: result.saleId,
        qtys: {item.id: 1},
        reason: 'Rusak',
      );
      expect(await stock(p), before - 24);
    });

    test('harga grosir dipakai saat checkout', () async {
      final p = await withPricing();
      final result = await checkout().checkout(
        cart: const Cart().add(p, qty: 10),
        cashier: kasir,
        storeId: store,
        paymentMethodId: tunai.id,
        paid: 33000,
      );
      expect(result.total, 33000);
      final item = (await db.salesDao.itemsOf(result.saleId)).single;
      expect(item.price, 3300);
      expect(item.unitFactor, 1);
    });

    test('transaksi tertahan menyimpan satuan', () async {
      final p = await withPricing();
      final repo = HeldCartRepository(db, clock: () => saleAt);
      await repo.hold(
        cart: const Cart().add(p, unit: p.units.single).add(p, qty: 3),
        cashier: kasir,
        storeId: store,
      );
      final held = (await repo.watchToday(storeId: store).first).single;
      final resumed = await repo.resume(held.id);
      expect(resumed.cart.lines.map((l) => (l.unitName, l.qty)), [
        ('DUS', 1),
        ('PCS', 3),
      ]);

      // Satuan dihapus admin sebelum dilanjutkan → dilewati.
      await repo.hold(
        cart: const Cart().add(p, unit: p.units.single),
        cashier: kasir,
        storeId: store,
      );
      await products.save(
        actor: admin,
        id: p.id,
        draft: ProductDraft(
          code: p.code,
          barcode: p.barcode,
          name: p.name,
          unitName: p.unitName,
          purchasePrice: p.purchasePrice,
          sellingPrice: p.defaultSellingPrice,
          units: const [],
        ),
      );
      final again = (await repo.watchToday(storeId: store).first).single;
      final r = await repo.resume(again.id);
      expect(r.cart.isEmpty, isTrue);
      expect(r.skipped.single, contains('(DUS)'));
    });

    test(
      'harga DUS & grosir khusus toko; toko lain tetap harga umum',
      () async {
        final p = await withPricing();
        final other = await StoreRepository(db)
            .save(actor: admin, name: 'Toko Cabang');
        await products.save(
          actor: admin,
          id: p.id,
          draft: ProductDraft(
            code: p.code,
            barcode: p.barcode,
            name: p.name,
            unitName: p.unitName,
            purchasePrice: p.purchasePrice,
            sellingPrice: p.defaultSellingPrice,
          ),
          stores: [
            StoreProductValues(
              storeId: other.id,
              stock: 0,
              unitPrices: const {'DUS': 75000},
              tiers: const [PriceTier(minQty: 6, price: 3250)],
            ),
          ],
        );
        final there = (await products.findByCodeOrBarcode(
          'BRG001',
          storeId: other.id,
        ))!;
        expect(there.units.single.price, 75000);
        expect(there.units.single.defaultPrice, 78000);
        expect(there.tiers, [const PriceTier(minQty: 6, price: 3250)]);
        final here = (await products.findByCodeOrBarcode(
          'BRG001',
          storeId: store,
        ))!;
        expect(here.units.single.price, 78000);
        expect(here.tiers, [const PriceTier(minQty: 10, price: 3300)]);
        // Tersimpan & terbaca lagi untuk form.
        final saved = (await products.storeValues(p.id))[other.id]!;
        expect(saved.unitPrices, {'DUS': 75000});
        expect(saved.tiers.single.price, 3250);
        // Keranjang di toko itu memakai harganya.
        final cart = const Cart().add(there, qty: 6);
        expect(cart.total, 6 * 3250);
        expect((await IntegrityService(db).check()).issues, isEmpty);
        // Harga sama dengan harga satuan = tanpa harga khusus.
        await products.save(
          actor: admin,
          id: p.id,
          draft: ProductDraft(
            code: p.code,
            barcode: p.barcode,
            name: p.name,
            unitName: p.unitName,
            purchasePrice: p.purchasePrice,
            sellingPrice: p.defaultSellingPrice,
          ),
          stores: [
            StoreProductValues(
              storeId: other.id,
              stock: 0,
              unitPrices: const {'DUS': 78000},
              tiers: const [],
            ),
          ],
        );
        expect(await db.select(db.storeUnitPrices).get(), isEmpty);
        final back = (await products.findByCodeOrBarcode(
          'BRG001',
          storeId: other.id,
        ))!;
        expect(back.tiers.single.price, 3300); // ikut grosir semua toko
      },
    );

    test('harga grosir diubah di luar aplikasi = ketahuan', () async {
      await withPricing();
      expect((await IntegrityService(db).check()).issues, isEmpty);
      await db.customStatement('UPDATE price_tiers SET price = 100');
      final report = await IntegrityService(db).check();
      expect(
        report.issues.map((i) => i.title),
        contains(contains('Satuan/harga grosir BRG001')),
      );
    });
  });

  group('Split payment', () {
    Future<CheckoutResult> splitSale() async {
      final p = (await products.findByCodeOrBarcode('BRG001'))!;
      // 6 × 3.500 = 21.000: QRIS 15.000 + tunai 10.000 (kembali 4.000).
      return checkout().checkout(
        cart: const Cart().add(p, qty: 6),
        cashier: kasir,
        storeId: store,
        split: [
          PaymentPart(
            methodId: qris.id,
            name: 'x',
            isCash: true, // jenis diambil dari database, bukan isian
            amount: 15000,
            ref: ' Q-1 ',
          ),
          PaymentPart(
            methodId: tunai.id,
            name: 'x',
            isCash: false,
            amount: 10000,
          ),
        ],
      );
    }

    test('tersimpan per metode, tunai dulu, kembalian dari tunai', () async {
      final r = await splitSale();
      expect(r.total, 21000);
      expect(r.change, 4000);
      expect(r.paid, 25000);
      expect(r.isCash, isTrue);
      expect(r.paymentMethod, 'Tunai + QRIS');
      final rows = await db.salesDao.paymentsOf(r.saleId);
      expect(rows.map((p) => (p.methodName, p.amount, p.tendered, p.ref)), [
        ('Tunai', 6000, 10000, null),
        ('QRIS', 15000, 15000, 'Q-1'),
      ]);

      final sale = (await SalesRepository(db).watchDay(saleAt).first).single;
      expect(sale.isSplit, isTrue);
      expect(DayTotal.of([sale]).byMethod, {'Tunai': 6000, 'QRIS': 15000});

      final report = ReportRepository(db, storeId: store);
      final range = ReportRange(saleAt, saleAt.add(const Duration(days: 1)));
      final byMethod = {
        for (final g in await report.payments(range)) g.name: g,
      };
      expect(byMethod['Tunai']!.revenue, 6000);
      expect(byMethod['QRIS']!.revenue, 15000);
      expect(byMethod['Tunai']!.transactions, 1);

      // Metode yang hanya dipakai sebagai bagian split tetap dianggap
      // terpakai (tidak bisa dihapus).
      expect(await db.paymentMethodsDao.countSalesUsing(qris.id), 1);
    });

    test('ditolak saat kurang, dan tidak bisa dipakai saat tukar', () async {
      final p = (await products.findByCodeOrBarcode('BRG001'))!;
      await expectLater(
        checkout().checkout(
          cart: const Cart().add(p, qty: 6),
          cashier: kasir,
          storeId: store,
          split: [
            PaymentPart(methodId: qris.id, name: '', isCash: false, amount: 1),
            PaymentPart(methodId: tunai.id, name: '', isCash: true, amount: 1),
          ],
        ),
        throwsA(
          isA<CheckoutFailure>().having(
            (e) => e.message,
            'message',
            contains('Uang tunai kurang'),
          ),
        ),
      );
      expect(await db.select(db.sales).get(), isEmpty);
    });

    test('retur faktur split: uang kembali tunai dulu, lalu QRIS', () async {
      final r = await splitSale();
      final item = (await db.salesDao.itemsOf(r.saleId)).single;
      final ret = ReturnService(db, clock: () => saleAt);

      // 1 barang (3.500) ← dari tunai.
      final first = await ret.create(
        actor: admin,
        saleId: r.saleId,
        qtys: {item.id: 1},
        reason: 'Salah ambil',
      );
      expect(first.refund, 3500);
      expect(first.paymentMethod, 'Tunai');
      expect(first.isCash, isTrue);

      // Sisa 5 barang (17.500) ← sisa tunai 2.500 + QRIS 15.000.
      final rest = await ret.create(
        actor: admin,
        saleId: r.saleId,
        qtys: {item.id: 5},
        reason: 'Batal',
      );
      expect(rest.refund, 17500);
      expect(rest.payments.map((p) => (p.name, p.amount)), [
        ('Tunai', -2500),
        ('QRIS', -15000),
      ]);
      expect(rest.refundMethods, 'Tunai Rp 2.500 + QRIS Rp 15.000');

      final day = await SalesRepository(db).watchDay(saleAt).first;
      expect(DayTotal.of(day).byMethod, {'Tunai': 0, 'QRIS': 0});
    });

    test('struk: rincian per metode; nota retur tercetak', () async {
      final settings = ReceiptSettingsRepository(db);
      final rasterizer = FakeRasterizer();
      final printer = ReceiptPrinter(db, settings, FakeTransport(), rasterizer);
      await settings.savePrinter(
        admin,
        const PrinterConfig(
          connection: PrinterConnection.system,
          printerName: 'Thermal 58',
        ),
      );
      final r = await splitSale();
      await printer.printSale(r.saleId);
      final html = rasterizer.html.single;
      expect(html, contains('Q-1'));
      expect(html, contains('15.000'));
      expect(html, contains('10.000')); // uang tunai diterima
      expect(html, contains('4.000')); // kembali
      expect(html, isNot(contains('NOTA RETUR')));

      final item = (await db.salesDao.itemsOf(r.saleId)).single;
      final ret = await ReturnService(db, clock: () => saleAt).create(
        actor: admin,
        saleId: r.saleId,
        qtys: {item.id: 2},
        reason: 'Kemasan sobek',
      );
      final data = await printer.load(ret.saleId);
      expect(data.isReturn, isTrue);
      expect(data.returnOf, r.invoiceNo);
      final values = data.toTemplateValues();
      expect(values['retur'], {
        'dari': r.invoiceNo,
        'alasan': 'Kemasan sobek',
        'kembali': '7.000',
      });

      await printer.printSale(ret.saleId);
      final returnHtml = rasterizer.html.last;
      expect(returnHtml, contains('NOTA RETUR'));
      expect(returnHtml, contains(r.invoiceNo));
      expect(returnHtml, contains('Kemasan sobek'));
      expect(returnHtml, contains('Dikembalikan'));
    });
  });

  test('v15 → v16: tabel satuan, grosir, split payment dibuat', () async {
    final schema = File('test/fixtures/schema_v15.sql').readAsStringSync();
    final old = AppDatabase(
      NativeDatabase.memory(
        setup: (Database raw) {
          for (final stmt in schema.split(';\n')) {
            if (stmt.trim().isNotEmpty) raw.execute(stmt);
          }
          raw.execute(
            "INSERT INTO users (username, full_name, password_hash, role) "
            "VALUES ('kasir', 'Kasir', 'x', 'kasir')",
          );
          raw.execute(
            "INSERT INTO products (code, name, selling_price, uuid) "
            "VALUES ('A1', 'Barang A', 5000, 'p-1')",
          );
          raw.execute(
            "INSERT INTO sales (invoice_no, sale_date, user_id, item_count, "
            "subtotal, total, paid, change_amount, payment_method) VALUES "
            "('INV-1', 1790000000, 1, 1, 5000, 5000, 5000, 0, 'Tunai')",
          );
          raw.execute(
            'INSERT INTO sale_items (sale_id, product_id, product_code, '
            'product_name, qty, price, purchase_price, subtotal) VALUES '
            "(1, 1, 'A1', 'Barang A', 1, 5000, 0, 5000)",
          );
          raw.userVersion = 15;
        },
      ),
    );
    addTearDown(old.close);
    expect((await old.select(old.saleItems).get()).single.unitFactor, 1);
    expect(await old.select(old.productUnits).get(), isEmpty);
    expect(await old.select(old.priceTiers).get(), isEmpty);
    expect(await old.select(old.salePayments).get(), isEmpty);
    final p = (await ProductRepository(old).findByCodeOrBarcode('A1'))!;
    expect(p.units, isEmpty);
    expect(p.tiers, isEmpty);
  });

  test('v18 → v19: grosir per toko, harga satuan per toko', () async {
    final schema = File('test/fixtures/schema_v18.sql').readAsStringSync();
    final old = AppDatabase(
      NativeDatabase.memory(
        setup: (Database raw) {
          for (final stmt in schema.split(';\n')) {
            if (stmt.trim().isNotEmpty) raw.execute(stmt);
          }
          raw.execute(
            "INSERT INTO products (code, name, selling_price, uuid) "
            "VALUES ('A1', 'Barang A', 5000, 'p-1')",
          );
          raw.execute(
            'INSERT INTO price_tiers (product_id, min_qty, price, uuid) '
            "VALUES (1, 10, 4500, 't-1')",
          );
          raw.userVersion = 18;
        },
      ),
    );
    addTearDown(old.close);
    final tier = (await old.select(old.priceTiers).get()).single;
    expect(tier.price, 4500);
    expect(tier.storeId, isNull);
    expect(await old.select(old.storeUnitPrices).get(), isEmpty);
    final p = (await ProductRepository(old).findByCodeOrBarcode('A1'))!;
    expect(p.tiers.single.price, 4500);
  });
}
