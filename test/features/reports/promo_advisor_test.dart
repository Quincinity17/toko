import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/reports/data/promo_repository.dart';
import 'package:toko/features/reports/domain/promo_advisor.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/domain/cart.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  final now = DateTime(2026, 10, 16, 12);

  PromoItem item(int id, {int price = 10000, int cost = 7000}) => PromoItem(
    productId: id,
    code: 'B$id',
    name: 'Barang $id',
    unit: 'PCS',
    price: price,
    purchasePrice: cost,
  );

  List<PromoSuggestion> only(PromoKind kind, PromoInput input) => [
    for (final s in PromoAdvisor.suggest(input))
      if (s.kind == kind) s,
  ];

  test('cuci gudang: lambat laku, urut modal tertahan, harga ≥ beli', () {
    final list = only(
      PromoKind.clearance,
      PromoInput(
        now: now,
        slow: [
          // Tidak laku 60 hari, stok 50 × 7.000 = 350.000.
          SlowItem(item: item(1), stock: 50, soldQty: 0),
          // Laku 1/hari, stok 30 → 30 hari: tidak lambat.
          SlowItem(item: item(2), stock: 30, soldQty: 60),
          // Stok 200, laku 60/60 hari = 200 hari → lambat; 200 × 9.500.
          SlowItem(
            item: item(3, cost: 9500),
            stock: 200,
            soldQty: 60,
            lastSold: now.subtract(const Duration(days: 3)),
          ),
          // Barang baru (10 hari): dilewati.
          SlowItem(
            item: item(4),
            stock: 100,
            soldQty: 0,
            createdAt: now.subtract(const Duration(days: 10)),
          ),
        ],
      ),
    );
    expect(list.map((s) => s.productIds.single), [3, 1]);
    // 10.000 × 85% = 8.500 tetapi harga beli 9.500 → min 9.700.
    expect(list.first.detail, contains('Rp 9.700'));
    expect(list.last.detail, contains('Rp 8.500 (−15%)'));
    expect(list.last.reason, contains('belum pernah terjual'));
    expect(list.last.reason, contains('Rp 350.000'));
  });

  test('paket hemat dari barang yang sering dibeli bersamaan', () {
    final list = only(
      PromoKind.bundle,
      PromoInput(
        now: now,
        pairTransactions: 100,
        pairs: [
          PairStat(
            a: item(1, price: 3500, cost: 2800),
            b: item(2, price: 5500, cost: 4200),
            together: 12,
            countA: 20,
            countB: 15,
          ),
          // Lift 3 × 100 / (60 × 50) = 0,1: kebetulan saja.
          PairStat(a: item(3), b: item(4), together: 3, countA: 60, countB: 50),
        ],
      ),
    );
    expect(list, hasLength(1));
    // (3.500 + 5.500) × 95% = 8.550 → 8.500.
    expect(list.single.detail, contains('Rp 8.500'));
    expect(list.single.reason, contains('12 transaksi'));
  });

  test('voucher naikkan belanja dari sebaran nilai belanja & margin', () {
    final s = only(
      PromoKind.basket,
      PromoInput(
        now: now,
        baskets: [for (var i = 1; i <= 40; i++) i * 2500], // 2.500 … 100.000
        margin: 0.2,
      ),
    ).single;
    final v = s.voucher!;
    // Median ±52.500, P75 ±75.000 → min. 75.000; potongan 5% = 3.750 →
    // 3.500, maks. 40% × 20% × 75.000 = 6.000.
    expect(v.minPurchase, 75000);
    expect(v.amount, 3500);
    expect(v.code, 'BELANJA75K');
    expect(
      only(PromoKind.basket, PromoInput(now: now, baskets: [1000, 2000])),
      isEmpty,
    );
  });

  test('jam sepi = rentang jam buka dengan omzet terendah', () {
    final s = only(
      PromoKind.quietHours,
      PromoInput(
        now: now,
        hourly: {
          8: 100000,
          9: 120000,
          10: 110000,
          13: 10000,
          14: 15000,
          16: 130000,
          17: 140000,
        },
      ),
    ).single;
    // 11–15 sepi (11, 12, 15 tanpa penjualan) → 11.00–16.00.
    expect(s.title, 'Promo jam 11.00–16.00');
  });

  test('barang umpan: sering dibeli dan margin ≥ 20%', () {
    final list = only(
      PromoKind.traffic,
      PromoInput(
        now: now,
        traffic: [
          TrafficItem(
            item: item(1),
            transactions: 40,
            revenue: 400000,
            cost: 280000,
          ),
          TrafficItem(
            item: item(2),
            transactions: 50,
            revenue: 500000,
            cost: 450000, // margin 10%
          ),
        ],
      ),
    );
    expect(list.map((s) => s.productIds.single), [1]);
  });

  test('dari database: pasangan & cuci gudang', () async {
    final db = await createSeededDb();
    addTearDown(db.close);
    final kasir = await AuthRepository(
      db,
      testHasher,
    ).login('kasir', 'kasir123');
    final store = await mainStoreId(db);
    final products = ProductRepository(db);
    final indomie = (await products.findByCodeOrBarcode('BRG001'))!;
    final teh = (await products.findByCodeOrBarcode('BRG010'))!;
    final aqua = (await products.findByCodeOrBarcode('BRG009'))!;
    final tunai = (await PaymentMethodRepository(
      db,
    ).watchAll().first).firstWhere((m) => m.name == 'Tunai');
    final checkout = CheckoutService(db, clock: () => now);
    Future<void> sell(Cart cart) => checkout.checkout(
      cart: cart,
      cashier: kasir,
      storeId: store,
      paymentMethodId: tunai.id,
      paid: 1000000,
    );
    for (var i = 0; i < 6; i++) {
      await sell(const Cart().add(indomie).add(teh));
    }
    for (var i = 0; i < 6; i++) {
      await sell(const Cart().add(aqua));
    }

    // Barang contoh dibuat "hari ini" → mundurkan supaya bukan barang baru.
    await db.customStatement('UPDATE products SET created_at = 1700000000');
    final input = await PromoRepository(
      db,
      storeId: store,
      clock: () => now,
    ).load();
    expect(input.pairTransactions, 12);
    final pair = input.pairs.single;
    expect({pair.a.productId, pair.b.productId}, {indomie.id, teh.id});
    expect(pair.together, 6);
    expect(input.baskets, hasLength(12));

    final suggestions = PromoAdvisor.suggest(input);
    expect(suggestions.where((s) => s.kind == PromoKind.bundle), hasLength(1));
    // Barang contoh lain tidak terjual dalam 60 hari → cuci gudang.
    final clearance = suggestions
        .where((s) => s.kind == PromoKind.clearance)
        .toList();
    expect(clearance, isNotEmpty);
    // Indomie terjual 6 dari stok 114 dalam 60 hari (±1.000 hari stok).
    final mie = clearance.firstWhere((s) => s.productIds.single == indomie.id);
    expect(mie.reason, contains('terjual 6 dalam 60 hari'));
  });

  test(
    'hasil promo: laku per hari sebelum vs sesudah; voucher dipakai',
    () async {
      final db = await createSeededDb();
      addTearDown(db.close);
      final kasir = await AuthRepository(
        db,
        testHasher,
      ).login('kasir', 'kasir123');
      final store = await mainStoreId(db);
      final indomie = (await ProductRepository(db)
          .findByCodeOrBarcode('BRG001'))!;
      final tunai = (await PaymentMethodRepository(
        db,
      ).watchAll().first).firstWhere((m) => m.name == 'Tunai');
      Future<void> sellAt(DateTime at, double qty) =>
          CheckoutService(db, clock: () => at).checkout(
            cart: const Cart().add(indomie, qty: qty),
            cashier: kasir,
            storeId: store,
            paymentMethodId: tunai.id,
            paid: 1000000,
          );
      final promoAt = DateTime(2026, 10, 10, 9);
      // Sebelum: 14 PCS dalam 14 hari = 1/hari.
      await sellAt(DateTime(2026, 10, 1, 10), 14);
      final repo = PromoRepository(db, storeId: store, clock: () => promoAt);
      await repo.record(
        PromoKind.clearance,
        'Indomie turun harga',
        productId: indomie.id,
      );
      await repo.record(PromoKind.basket, 'Voucher', voucherCode: 'HEMAT');
      // Sesudah: 21 PCS dalam 7 hari = 3/hari.
      await sellAt(DateTime(2026, 10, 12, 10), 21);
      final results = await PromoRepository(
        db,
        storeId: store,
        clock: () => DateTime(2026, 10, 16, 20),
      ).results();
      final product = results.firstWhere((r) => !r.isVoucher);
      expect(product.daysAfter, 7);
      expect(product.perDayBefore, 1);
      expect(product.perDayAfter, 3);
      expect(product.change, closeTo(2, 1e-9));
      final voucher = results.firstWhere((r) => r.isVoucher);
      expect(voucher.uses, 0);
      expect(voucher.basketAfter, 21 * 3500);
    },
  );
}
