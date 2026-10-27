import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/core/database/tables/audit.dart';
import 'package:toko/features/audit/data/integrity_service.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/payments/domain/payment_method.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/products/domain/product.dart';
import 'package:toko/features/reports/data/report_repository.dart';
import 'package:toko/features/reports/domain/report_models.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/data/held_cart_repository.dart';
import 'package:toko/features/sales/data/return_service.dart';
import 'package:toko/features/sales/data/sales_repository.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/vouchers/data/voucher_repository.dart';
import 'package:toko/features/vouchers/domain/voucher.dart';

import '../../helpers/test_app.dart';

Voucher _voucher(
  VoucherType type,
  double value, {
  int? maxDiscount,
  int minPurchase = 0,
  DateTime? start,
  DateTime? end,
  int? storeId,
}) => Voucher(
  id: 1,
  code: 'TES',
  type: type,
  value: value,
  maxDiscount: maxDiscount,
  minPurchase: minPurchase,
  startDate: start,
  endDate: end,
  storeId: storeId,
);

Product _product(int id, int price) => Product(
  id: id,
  code: 'P$id',
  name: 'Barang $id',
  purchasePrice: price - 500,
  sellingPrice: price,
  stock: 100,
  minStock: 0,
);

void main() {
  // Pesan voucher memuat tanggal berformat Indonesia.
  setUpAll(() => initializeDateFormatting('id_ID'));

  group('aturan voucher (domain)', () {
    final now = DateTime(2026, 10, 15, 13);

    test('persen dengan batas maksimal', () {
      final cart = const Cart()
          .add(_product(1, 10000), qty: 10)
          .withVoucher(_voucher(VoucherType.percent, 10, maxDiscount: 5000));
      expect(cart.discount, 5000); // 10% dari 100.000 = 10.000 → dibatasi
      expect(cart.total, 95000);
    });

    test('belum berlaku sampai minimal belanja terpenuhi', () {
      var cart = const Cart()
          .add(_product(1, 10000))
          .withVoucher(_voucher(VoucherType.amount, 5000, minPurchase: 25000));
      expect(cart.voucherShortfall, 15000);
      expect(cart.discount, 0);
      cart = cart.setQty(0, 3);
      expect(cart.voucherShortfall, 0);
      expect(cart.discount, 5000);
      // Voucher tetap terpasang saat barang ditambah/dihapus.
      expect(cart.add(_product(2, 1000)).voucher, isNotNull);
      expect(cart.removeAt(0).voucher, isNotNull);
    });

    test('nominal tidak melebihi subtotal', () {
      final cart = const Cart()
          .add(_product(1, 3000))
          .withVoucher(_voucher(VoucherType.amount, 10000));
      expect(cart.discount, 3000);
      expect(cart.total, 0);
    });

    test('status mengikuti tanggal dan aktif', () {
      expect(
        _voucher(VoucherType.amount, 1000).statusAt(now),
        VoucherStatus.active,
      );
      expect(
        _voucher(
          VoucherType.amount,
          1000,
          start: DateTime(2026, 10, 16),
        ).statusAt(now),
        VoucherStatus.scheduled,
      );
      // Berlaku sampai akhir hari tanggal berakhir.
      expect(
        _voucher(
          VoucherType.amount,
          1000,
          end: DateTime(2026, 10, 15),
        ).statusAt(now),
        VoucherStatus.active,
      );
      expect(
        _voucher(
          VoucherType.amount,
          1000,
          end: DateTime(2026, 10, 14),
        ).statusAt(now),
        VoucherStatus.expired,
      );
    });

    test('voucher satu toko ditolak di toko lain', () {
      final v = _voucher(VoucherType.amount, 1000, storeId: 1);
      expect(v.problemFor(subtotal: 5000, now: now, storeId: 1), isNull);
      expect(
        v.problemFor(subtotal: 5000, now: now, storeId: 2),
        contains('tidak berlaku di toko ini'),
      );
      final all = _voucher(VoucherType.amount, 1000);
      expect(all.problemFor(subtotal: 5000, now: now, storeId: 2), isNull);
    });

    test('aturan isian form', () {
      expect(VoucherRules.code('hemat 10'), isNotNull);
      expect(VoucherRules.code('hemat10'), isNull);
      expect(VoucherRules.value(VoucherType.percent, 120), isNotNull);
      expect(VoucherRules.value(VoucherType.amount, 0), isNotNull);
      expect(
        VoucherRules.period(DateTime(2026, 10, 2), DateTime(2026, 10, 1)),
        isNotNull,
      );
    });
  });

  group('voucher di database', () {
    late AppDatabase db;
    late ProductRepository products;
    late AppUser kasir;
    late AppUser admin;
    late PaymentMethod tunai;
    late int mainStore;
    final clock = DateTime(2026, 9, 30, 10, 15);

    setUp(() async {
      db = await createSeededDb();
      products = ProductRepository(db);
      final auth = AuthRepository(db, testHasher);
      kasir = await auth.login('kasir', 'kasir123');
      admin = await auth.login('admin', 'admin123');
      tunai = (await PaymentMethodRepository(
        db,
      ).watchAll().first).firstWhere((m) => m.name == 'Tunai');
      mainStore = await mainStoreId(db);
    });

    tearDown(() => db.close());

    VoucherRepository vouchers() => VoucherRepository(db, clock: () => clock);
    CheckoutService service() => CheckoutService(db, clock: () => clock);

    Future<Cart> cartOf(String code, {double qty = 1}) async =>
        const Cart().add((await products.findByCodeOrBarcode(code))!, qty: qty);

    Future<Voucher> create({
      String code = 'HEMAT10',
      VoucherType type = VoucherType.percent,
      double value = 10,
      int? maxDiscount,
      int minPurchase = 0,
      DateTime? end,
      int? storeId,
    }) => vouchers().save(
      actor: admin,
      draft: VoucherDraft(
        code: code,
        type: type,
        value: value,
        maxDiscount: maxDiscount,
        minPurchase: minPurchase,
        endDate: end,
        storeId: storeId,
      ),
    );

    Future<CheckoutResult> pay(Cart cart, {int paid = 100000}) =>
        service().checkout(
          cart: cart,
          cashier: kasir,
          storeId: mainStore,
          paymentMethodId: tunai.id,
          paid: paid,
        );

    test('dipakai saat checkout: potongan & kode tersimpan, tercatat '
        'di aktivitas, keutuhan data bersih', () async {
      // Jam sungguhan (seperti login di setUp) supaya pemeriksaan keutuhan
      // tidak melihat jam mundur.
      final repo = VoucherRepository(db);
      await repo.save(
        actor: admin,
        draft: const VoucherDraft(
          code: 'HEMAT10',
          type: VoucherType.percent,
          value: 10,
          maxDiscount: 5000,
        ),
      );
      final v = await repo.findUsable('hemat10', storeId: mainStore);
      final cart = (await cartOf('BRG005')).withVoucher(v); // 76.000

      final result = await CheckoutService(db).checkout(
        cart: cart,
        cashier: kasir,
        storeId: mainStore,
        paymentMethodId: tunai.id,
        paid: 100000,
      );
      expect(result.discount, 5000); // 7.600 dibatasi 5.000
      expect(result.total, 71000);
      expect(result.voucherCode, 'HEMAT10');

      final sale = (await SalesRepository(
        db,
      ).watchDay(DateTime.now()).first).single;
      expect(sale.voucherCode, 'HEMAT10');
      expect(sale.discount, 5000);
      expect(sale.subtotal, 76000);

      final audit = await db.select(db.auditLog).get();
      expect(
        audit.map((a) => a.type),
        containsAll([AuditType.voucherChanged, AuditType.sale]),
      );
      expect(
        audit.lastWhere((a) => a.type == AuditType.sale).summary,
        contains('voucher HEMAT10'),
      );
      final issues = (await IntegrityService(db).check()).issues;
      expect([for (final i in issues) '${i.title}: ${i.detail}'], isEmpty);
    });

    test(
      'dinonaktifkan atau diubah admin setelah dipasang → ditolak',
      () async {
        final created = await create(type: VoucherType.amount, value: 1000);
        final v = await vouchers().findUsable('HEMAT10', storeId: mainStore);
        final cart = (await cartOf('BRG009')).withVoucher(v);

        // Nilai diubah: total yang dilihat kasir sudah tidak sama.
        await vouchers().save(
          actor: admin,
          id: created.id,
          draft: const VoucherDraft(
            code: 'HEMAT10',
            type: VoucherType.amount,
            value: 2000,
          ),
        );
        await expectLater(
          pay(cart, paid: 5000),
          throwsA(isA<CheckoutFailure>()),
        );

        await vouchers().save(
          actor: admin,
          id: created.id,
          draft: const VoucherDraft(
            code: 'HEMAT10',
            type: VoucherType.amount,
            value: 1000,
            isActive: false,
          ),
        );
        await expectLater(
          pay(cart, paid: 5000),
          throwsA(isA<CheckoutFailure>()),
        );
        expect(
          vouchers().findUsable('HEMAT10', storeId: mainStore),
          throwsA(isA<VoucherFailure>()),
        );
        expect(await db.select(db.sales).get(), isEmpty);
      },
    );

    test(
      'voucher toko lain ditolak; tanpa kuota bisa dipakai berkali-kali',
      () async {
        final cabang = await db.storesDao.insertStore(
          StoresCompanion.insert(name: 'Cabang'),
        );
        await create(code: 'CABANG', storeId: cabang);
        expect(
          vouchers().findUsable('CABANG', storeId: mainStore),
          throwsA(isA<VoucherFailure>()),
        );

        await create(type: VoucherType.amount, value: 500);
        for (var i = 0; i < 3; i++) {
          final v = await vouchers().findUsable('HEMAT10', storeId: mainStore);
          await pay((await cartOf('BRG009')).withVoucher(v), paid: 5000);
        }
        expect(await db.select(db.sales).get(), hasLength(3));
      },
    );

    test('minimal belanja diperiksa ulang saat checkout', () async {
      await create(type: VoucherType.amount, value: 5000, minPurchase: 50000);
      final v = await vouchers().findUsable('HEMAT10', storeId: mainStore);
      expect(
        pay((await cartOf('BRG009')).withVoucher(v), paid: 5000),
        throwsA(isA<CheckoutFailure>()),
      );
    });

    test('kedaluwarsa dan tidak ada ditolak', () async {
      await create(end: DateTime(2026, 9, 29));
      expect(
        vouchers().findUsable('HEMAT10', storeId: mainStore),
        throwsA(isA<VoucherFailure>()),
      );
      expect(
        vouchers().findUsable('TIDAKADA', storeId: mainStore),
        throwsA(isA<VoucherFailure>()),
      );
    });

    test('kode unik, kasir tidak boleh membuat, terpakai tidak bisa dihapus '
        'atau diganti kodenya', () async {
      final v = await create(type: VoucherType.amount, value: 1000);
      expect(create(code: 'hemat10'), throwsA(isA<VoucherFailure>()));
      expect(
        vouchers().save(
          actor: kasir,
          draft: const VoucherDraft(
            code: 'KASIR',
            type: VoucherType.amount,
            value: 1000,
          ),
        ),
        throwsA(isA<VoucherFailure>()),
      );
      await pay((await cartOf('BRG009')).withVoucher(v), paid: 5000);
      expect(
        vouchers().delete(actor: admin, id: v.id),
        throwsA(isA<VoucherFailure>()),
      );
      expect(
        vouchers().save(
          actor: admin,
          id: v.id,
          draft: const VoucherDraft(
            code: 'GANTI',
            type: VoucherType.amount,
            value: 1000,
          ),
        ),
        throwsA(isA<VoucherFailure>()),
      );
      // Yang belum dipakai bisa dihapus.
      final lain = await create(code: 'LAIN');
      await vouchers().delete(actor: admin, id: lain.id);
      expect((await vouchers().watchAll().first).map((v) => v.code), [
        'HEMAT10',
      ]);
    });

    test(
      'batal faktur bervoucher: hanya batal semua, laporan kembali nol',
      () async {
        await create(type: VoucherType.amount, value: 2000);
        final v = await vouchers().findUsable('HEMAT10', storeId: mainStore);
        final cart = (await cartOf(
          'BRG001',
          qty: 2,
        )).add((await products.findByCodeOrBarcode('BRG009'))!).withVoucher(v);
        final sold = await pay(cart, paid: 20000); // 10.500 − 2.000
        expect(sold.total, 8500);

        final returns = ReturnService(db, clock: () => clock);
        final sale = await returns.load(sold.saleId);
        expect(sale.hasDiscount, isTrue);
        expect(
          returns.create(
            actor: admin,
            saleId: sold.saleId,
            qtys: {sale.lines.first.saleItemId: 1},
            reason: 'Sebagian',
          ),
          throwsA(isA<ReturnFailure>()),
        );
        final r = await returns.create(
          actor: admin,
          saleId: sold.saleId,
          qtys: {for (final l in sale.lines) l.saleItemId: l.returnable},
          reason: 'Batal',
        );
        expect(r.refund, 8500);

        final report = ReportRepository(db, clock: () => clock);
        final range = ReportRange(DateTime(2026, 9, 30), DateTime(2026, 10, 1));
        final s = await report.summary(range);
        expect(s.revenue, 0);
        expect(s.grossSales, 0);
        expect(s.discount, 0);
        final perVoucher = (await report.vouchers(range)).single;
        expect(perVoucher.name, 'HEMAT10');
        expect(perVoucher.transactions, 1);
        expect(perVoucher.discount, 0);
        expect(perVoucher.revenue, 0);
      },
    );

    test('transaksi tertahan menyimpan total sebelum voucher', () async {
      await create(type: VoucherType.amount, value: 1000);
      final v = await vouchers().findUsable('HEMAT10', storeId: mainStore);
      final cart = (await cartOf('BRG009')).withVoucher(v);
      await HeldCartRepository(
        db,
        clock: () => clock,
      ).hold(cart: cart, cashier: kasir, storeId: mainStore);
      final held = await db.select(db.heldCarts).getSingle();
      expect(held.total, cart.subtotal);
    });
  });
}
