import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/database/tables/sales.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/domain/cart.dart';
import 'package:toko/features/stock/data/stock_repository.dart';
import 'package:toko/features/stock/domain/stock_adjustment.dart';
import 'package:toko/features/stock/domain/stock_alert.dart';
import 'package:toko/features/stock/presentation/stock_alert_list.dart';

import '../../helpers/test_app.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  StockHealthRow row(
    double stock, {
    double min = 0,
    double sold = 0,
    double adjustedOut = 0,
    String unit = 'PCS',
  }) => StockHealthRow(
    productId: stock.hashCode,
    code: 'X',
    name: 'Barang',
    unit: unit,
    stock: stock,
    minStock: min,
    sold: sold,
    adjustedOut: adjustedOut,
  );

  List<StockAlertKind> kinds(StockHealthRow r) => [
    for (final a in StockAlerts.analyze([r])) a.kind,
  ];

  test('minus, habis padahal laku, menipis, akan habis', () {
    expect(kinds(row(-3, sold: 30)), [StockAlertKind.negative]);
    expect(kinds(row(0, sold: 30)), [StockAlertKind.outOfStock]);
    expect(kinds(row(0)), isEmpty); // habis tapi tidak laku: diam saja
    expect(kinds(row(4, min: 5)), [StockAlertKind.low]);
    // Laku 3/hari, sisa 15 → habis 5 hari lagi.
    expect(kinds(row(15, sold: 90)), [StockAlertKind.runningOut]);
    expect(kinds(row(40, sold: 90)), isEmpty);
  });

  test('saran beli: cukup 14 hari (min. 2 × stok minimum)', () {
    // Laku 3/hari → target 42; stok −3 → beli 45.
    expect(StockAlerts.analyze([row(-3, sold: 90)]).single.suggestedBuy, 45);
    // Tidak laku, min 5 → target 10; stok 4 → beli 6.
    expect(StockAlerts.analyze([row(4, min: 5)]).single.suggestedBuy, 6);
    // Satuan timbangan: 1 desimal.
    final kg = StockAlerts.analyze([row(0.5, min: 1.2, unit: 'KG')]).single;
    expect(kg.suggestedBuy, closeTo(1.9, 1e-9));
  });

  test('stok tidak sesuai kenyataan', () {
    expect(kinds(row(2.5)), [StockAlertKind.fractional]);
    expect(kinds(row(2.5, unit: 'kg')), isEmpty);
    // Laku 1/hari, stok 1000 = ±33 bulan.
    expect(kinds(row(1000, sold: 30)), [StockAlertKind.excessive]);
    // Berkurang 12 lewat penyesuaian, terjual 20, stok 30.
    expect(kinds(row(30, sold: 20, adjustedOut: 12)), [
      StockAlertKind.shrinkage,
    ]);
    expect(kinds(row(300, sold: 300, adjustedOut: 6)), isEmpty);
  });

  test('urutan: bahaya, beli, cek', () {
    final list = StockAlerts.analyze([
      row(2.5),
      row(4, min: 5),
      row(-1),
      row(-9),
    ]);
    expect(list.map((a) => a.kind), [
      StockAlertKind.negative,
      StockAlertKind.negative,
      StockAlertKind.low,
      StockAlertKind.fractional,
    ]);
    expect(list.first.row.stock, -9);
  });

  test('dari database: penjualan & penyesuaian 30 hari terakhir', () async {
    final db = await createSeededDb();
    addTearDown(db.close);
    final auth = AuthRepository(db, testHasher);
    final admin = await auth.login('admin', 'admin123');
    final kasir = await auth.login('kasir', 'kasir123');
    final store = await mainStoreId(db);
    final products = ProductRepository(db);
    final p = (await products.findByCodeOrBarcode('BRG001', storeId: store))!;

    // Opname jadi 2, lalu terjual 5 → minus 3.
    await StockRepository(db).adjust(
      actor: admin,
      storeId: store,
      productId: p.id,
      mode: StockAdjustMode.count,
      qty: 2,
    );
    final tunai = (await PaymentMethodRepository(
      db,
    ).watchAll().first).firstWhere((m) => m.name == 'Tunai');
    await CheckoutService(db).checkout(
      cart: const Cart().add(p, qty: 5),
      cashier: kasir,
      storeId: store,
      paymentMethodId: tunai.id,
      paid: 50000,
    );
    final alerts = await StockAlertRepository(db).watch(store).first;
    final mine = alerts.where((a) => a.row.productId == p.id).toList();
    expect(mine.first.kind, StockAlertKind.negative);
    expect(mine.first.row.stock, -3);
    expect(mine.first.row.sold, 5);
    // Opname mengurangi 118 → banyak berkurang di luar penjualan.
    expect(mine.map((a) => a.kind), contains(StockAlertKind.shrinkage));
    expect(
      (await db.select(db.stockMovements).get()).map((m) => m.type),
      containsAll([StockMovementType.adjust, StockMovementType.sale]),
    );
  });

  test('ambang bisa diatur; nilai di luar batas dipotong', () {
    // Laku 3/hari, sisa 15 = 5 hari: "akan habis" bila batas 7, tidak bila 3.
    expect(kinds(row(15, sold: 90)), [StockAlertKind.runningOut]);
    expect(
      StockAlerts.analyze([
        row(15, sold: 90),
      ], settings: const StockAlertSettings(runningOutDays: 3)),
      isEmpty,
    );
    // Saran beli cukup 30 hari: target 90 − 15 = 75.
    expect(
      StockAlerts.analyze([
        row(15, sold: 90),
      ], settings: const StockAlertSettings(coverDays: 30)).single.suggestedBuy,
      75,
    );
    final s = StockAlertSettings.fromJson(
      '{"days": 1, "runningOutDays": 500, "coverDays": 20}',
    );
    expect(s.days, 7);
    expect(s.runningOutDays, 60);
    expect(s.coverDays, 20);
    expect(s.excessiveDays, 365);
    expect(StockAlertSettings.fromJson('rusak').days, 30);
  });

  test('semua toko: peringatan diberi nama toko + daftar belanja', () async {
    final db = await createSeededDb();
    addTearDown(db.close);
    final admin = await AuthRepository(
      db,
      testHasher,
    ).login('admin', 'admin123');
    final store = await mainStoreId(db);
    final p = (await ProductRepository(db).findByCodeOrBarcode('BRG001'))!;
    // Stok minus (mis. terjual tanpa barang masuk tercatat).
    await db.storesDao.changeStock(
      storeId: store,
      productId: p.id,
      delta: -(p.stock + 2),
      type: StockMovementType.sale,
      userId: null,
    );
    final repo = StockAlertRepository(db);
    final all = await repo.watch(null).first;
    final mine = all.firstWhere((a) => a.row.productId == p.id);
    expect(mine.kind, StockAlertKind.negative);
    expect(mine.row.storeName, 'Toko Utama');
    expect((await repo.watch(store).first).first.row.storeName, isNull);

    await repo.saveSettings(admin, const StockAlertSettings(coverDays: 21));
    expect((await repo.settings()).coverDays, 21);
    final kasir = await AuthRepository(
      db,
      testHasher,
    ).login('kasir', 'kasir123');
    await expectLater(
      repo.saveSettings(kasir, const StockAlertSettings()),
      throwsA(isA<StockFailure>()),
    );

    final text = shoppingListText([
      StockAlert(
        row: row(-2),
        kind: StockAlertKind.negative,
        message: '',
        suggestedBuy: 10,
      ),
    ], at: DateTime(2026, 10, 17));
    expect(text, contains('Barang (X): 10 PCS'));
    expect(shoppingListXlsx([mine]), isNotEmpty);
  });
}
