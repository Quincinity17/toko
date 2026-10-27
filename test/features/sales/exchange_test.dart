import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/audit/data/integrity_service.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/payments/domain/payment_method.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/data/exchange_service.dart';
import 'package:toko/features/sales/data/return_service.dart';
import 'package:toko/features/sales/data/sales_repository.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/sales/domain/day_total.dart';
import 'package:toko/features/sales/domain/exchange.dart';
import 'package:toko/features/sales/domain/split_payment.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late AppUser admin;
  late AppUser kasir;
  late int store;
  late PaymentMethod tunai;
  late PaymentMethod qris;
  late ProductRepository products;

  setUpAll(() => initializeDateFormatting('id_ID'));

  setUp(() async {
    db = await createSeededDb();
    final auth = AuthRepository(db, testHasher);
    admin = await auth.login('admin', 'admin123');
    kasir = await auth.login('kasir', 'kasir123');
    store = await mainStoreId(db);
    final methods = await PaymentMethodRepository(db).watchAll().first;
    tunai = methods.firstWhere((m) => m.name == 'Tunai');
    qris = methods.firstWhere((m) => m.name == 'QRIS');
    products = ProductRepository(db);
  });
  tearDown(() => db.close());

  Future<Product> product(String code) async =>
      (await products.findByCodeOrBarcode(code, storeId: store))!;

  /// Indomie Rp 3.500, Teh Botol Rp 5.500.
  Future<int> sell(
    String code, {
    double qty = 1,
    PaymentMethod? method,
  }) async => (await CheckoutService(db).checkout(
    cart: const Cart().add(await product(code), qty: qty),
    cashier: kasir,
    storeId: store,
    paymentMethodId: (method ?? tunai).id,
    paid: 100000,
  )).saleId;

  Future<Map<int, double>> one(int saleId) async {
    final s = await ReturnService(db).load(saleId);
    return {s.lines.first.saleItemId: 1};
  }

  Future<DayTotal> today() async =>
      DayTotal.of(await SalesRepository(db).watchDay(DateTime.now()).first);

  test('hitungan selisih', () {
    const more = ExchangeTotals(credit: 3500, newTotal: 5500);
    expect(more.customerPays, 2000);
    expect(more.refund, 0);
    const less = ExchangeTotals(credit: 5500, newTotal: 3500);
    expect(less.customerPays, 0);
    expect(less.refund, 2000);
  });

  test('tukar ke barang lebih mahal: pelanggan menambah; stok & tutup kasir '
      'benar; keutuhan data bersih', () async {
    final saleId = await sell('BRG001', qty: 2); // 7.000
    final indomie = await product('BRG001');
    final teh = await product('BRG010');

    final r = await ExchangeService(db).exchange(
      actor: admin,
      saleId: saleId,
      qtys: await one(saleId),
      reason: 'Ganti rasa',
      replacement: const Cart().add(teh),
      paymentMethodId: tunai.id,
      paid: 5000,
    );
    expect(r.returned.invoiceNo, startsWith('RET-'));
    expect(r.returned.refund, 3500);
    expect(r.sale.invoiceNo, startsWith('INV-'));
    expect(r.sale.total, 5500);
    expect(r.sale.credit, 3500);
    expect(r.sale.paid, 3500 + 5000);
    expect(r.sale.change, 3000); // bayar 5.000 untuk selisih 2.000

    final saved = await (db.select(
      db.sales,
    )..where((s) => s.id.equals(r.sale.saleId))).getSingle();
    expect(saved.exchangeOfId, r.returned.saleId);
    final ret = await (db.select(
      db.sales,
    )..where((s) => s.id.equals(r.returned.saleId))).getSingle();
    expect(ret.returnReason, 'Tukar barang: Ganti rasa');

    expect((await product('BRG001')).stock, indomie.stock + 1);
    expect((await product('BRG010')).stock, teh.stock - 1);

    // Laci: 7.000 + selisih 2.000.
    final t = await today();
    expect(t.byMethod['Tunai'], 9000);
    expect(t.transactions, 2); // faktur asal + faktur tukar

    expect((await IntegrityService(db).check()).issues, isEmpty);
  });

  test('tukar ke barang lebih murah: kelebihan dikembalikan', () async {
    final saleId = await sell('BRG010'); // 5.500
    final r = await ExchangeService(db).exchange(
      actor: admin,
      saleId: saleId,
      qtys: await one(saleId),
      reason: 'Salah ambil',
      replacement: const Cart().add(await product('BRG001')),
      paymentMethodId: tunai.id,
    );
    expect(r.sale.total, 3500);
    expect(r.sale.change, 2000);
    expect((await today()).byMethod['Tunai'], 3500); // 5.500 − 2.000
  });

  test(
    'faktur asal QRIS, selisih tunai: per metode = uang yang berpindah',
    () async {
      final saleId = await sell('BRG001', qty: 2, method: qris);
      await ExchangeService(db).exchange(
        actor: admin,
        saleId: saleId,
        qtys: await one(saleId),
        reason: 'Ganti',
        replacement: const Cart().add(await product('BRG010')),
        paymentMethodId: tunai.id,
        paid: 2000,
      );
      final t = await today();
      expect(t.byMethod['QRIS'], 7000);
      expect(t.byMethod['Tunai'], 2000);
      expect(t.total, 9000);
    },
  );

  test('gagal di tengah = tidak ada yang tersimpan', () async {
    final saleId = await sell('BRG001', qty: 2);
    final before = await db.select(db.sales).get();
    final indomie = await product('BRG001');

    // Uang kurang untuk selisih.
    await expectLater(
      ExchangeService(db).exchange(
        actor: admin,
        saleId: saleId,
        qtys: await one(saleId),
        reason: 'Ganti',
        replacement: const Cart().add(await product('BRG010')),
        paymentMethodId: tunai.id,
        paid: 1000,
      ),
      throwsA(isA<CheckoutFailure>()),
    );
    // Kasir tanpa hak retur.
    await expectLater(
      ExchangeService(db).exchange(
        actor: kasir,
        saleId: saleId,
        qtys: await one(saleId),
        reason: 'Ganti',
        replacement: const Cart().add(await product('BRG010')),
        paymentMethodId: tunai.id,
        paid: 5000,
      ),
      throwsA(isA<ReturnFailure>()),
    );
    // Tanpa barang pengganti.
    await expectLater(
      ExchangeService(db).exchange(
        actor: admin,
        saleId: saleId,
        qtys: await one(saleId),
        reason: 'Ganti',
        replacement: const Cart(),
        paymentMethodId: tunai.id,
      ),
      throwsA(isA<CheckoutFailure>()),
    );

    expect(await db.select(db.sales).get(), hasLength(before.length));
    expect((await product('BRG001')).stock, indomie.stock);
  });

  test('cari faktur lama dari nomornya (toko sendiri)', () async {
    await sell('BRG001');
    await sell('BRG010');
    final repo = SalesRepository(db);
    final all = await repo.search('inv', storeId: store);
    expect(all, hasLength(2));
    final last = all.first.invoiceNo; // terbaru dulu
    expect(last, endsWith('0002'));
    final exact = await repo.search(last.toLowerCase(), storeId: store);
    expect(exact.single.invoiceNo, last);
    expect(await repo.search('inv', storeId: store + 99), isEmpty);
    expect(await repo.search('%', storeId: store), isEmpty);
  });

  test('tukar + bayar terpisah: selisih dibayar tunai & QRIS; tutup kasir '
      'per metode = uang yang berpindah', () async {
    final saleId = await sell('BRG001'); // 3.500 tunai
    // Ganti dengan 3 Teh Botol (16.500): pelanggan menambah 13.000 =
    // QRIS 10.000 + tunai 3.000 (diterima 5.000, kembali 2.000).
    final r = await ExchangeService(db).exchange(
      actor: admin,
      saleId: saleId,
      qtys: await one(saleId),
      reason: 'Ganti barang',
      replacement: const Cart().add(await product('BRG010'), qty: 3),
      split: [
        PaymentPart(
          methodId: qris.id,
          name: 'QRIS',
          isCash: false,
          amount: 10000,
        ),
        PaymentPart(
          methodId: tunai.id,
          name: 'Tunai',
          isCash: true,
          amount: 5000,
        ),
      ],
    );
    expect(r.sale.total, 16500);
    expect(r.sale.change, 2000);
    expect(r.returned.paymentMethod, 'Tunai');
    final day = await today();
    // Tunai: 3.500 (jual) − 3.500 (kredit) + 3.500 + 3.000 ... bersih:
    // faktur asal 3.500 + tukar tunai 3.000 = 6.500; QRIS 10.000.
    expect(day.byMethod, {'Tunai': 6500, 'QRIS': 10000});
    expect(day.total, 16500);
    final sale = (await SalesRepository(
      db,
    ).watchDay(DateTime.now()).first).firstWhere((x) => x.id == r.sale.saleId);
    expect(sale.payments.map((p) => (p.name, p.tendered)), [
      ('Tunai', 5000),
      ('QRIS', 10000),
    ]);
    expect((await IntegrityService(db).check()).issues, isEmpty);
  });
}
