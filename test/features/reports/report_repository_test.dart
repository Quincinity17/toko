import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:toko/core/database/app_database.dart';
import 'package:toko/features/auth/data/auth_repository.dart';
import 'package:toko/features/auth/domain/app_user.dart';
import 'package:toko/features/payments/data/payment_method_repository.dart';
import 'package:toko/features/payments/domain/payment_method.dart';
import 'package:toko/features/products/data/product_repository.dart';
import 'package:toko/features/reports/data/report_export.dart';
import 'package:toko/features/reports/data/report_repository.dart';
import 'package:toko/features/reports/domain/report_models.dart';
import 'package:toko/features/sales/data/checkout_service.dart';
import 'package:toko/features/sales/data/sales_repository.dart';
import 'package:toko/features/sales/domain/cart.dart';

import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late AppUser kasir;
  late PaymentMethod tunai;
  late PaymentMethod qris;
  late ProductRepository products;

  // "Hari ini" untuk tes: Kamis 15 Okt 2026.
  final today = DateTime(2026, 10, 15);
  DateTime at(int dayOffset, int hour, [int minute = 0]) =>
      DateTime(today.year, today.month, today.day + dayOffset, hour, minute);

  setUpAll(() => initializeDateFormatting('id_ID'));

  setUp(() async {
    db = await createSeededDb();
    final auth = AuthRepository(db, testHasher);
    kasir = await auth.login('kasir', 'kasir123');
    final methods = await PaymentMethodRepository(db).watchAll().first;
    tunai = methods.firstWhere((m) => m.name == 'Tunai');
    qris = methods.firstWhere((m) => m.name == 'QRIS');
    products = ProductRepository(db);
  });

  tearDown(() => db.close());

  Future<void> sell(
    DateTime when,
    Map<String, double> items, {
    PaymentMethod? method,
  }) async {
    var cart = const Cart();
    for (final e in items.entries) {
      cart = cart.add(
        (await products.findByCodeOrBarcode(e.key))!,
        qty: e.value,
      );
    }
    await CheckoutService(db, clock: () => when).checkout(
      cart: cart,
      cashier: kasir,
      storeId: await mainStoreId(db),
      paymentMethodId: (method ?? tunai).id,
      paid: 1000000,
    );
  }

  ReportRepository repo() => ReportRepository(db, clock: () => at(0, 20));

  /// Indomie (BRG001): jual 3.500, beli 2.800. Aqua (BRG009): 3.500 / 2.800.
  /// Teh Botol (BRG010): 5.500 / 4.200.
  Future<void> seedSales() async {
    await sell(at(-1, 10), {'BRG001': 2}); // kemarin
    await sell(at(0, 9, 15), {'BRG009': 1, 'BRG010': 1}, method: qris);
    await sell(at(0, 14, 30), {'BRG001': 3});
  }

  test('ringkasan hari ini dan perbandingan dengan kemarin', () async {
    await seedSales();
    final r = repo();
    final range = ReportRange.preset(RangePreset.today, at(0, 20));
    final s = await r.summary(range);

    // Omzet: (3.500 + 5.500) + 3 × 3.500 = 9.000 + 10.500
    expect(s.transactions, 2);
    expect(s.grossSales, 19500);
    expect(s.discount, 0);
    expect(s.revenue, 19500);
    // Pokok: 2.800 + 4.200 + 3 × 2.800 = 15.400
    expect(s.cost, 15400);
    expect(s.grossProfit, 4100);
    expect(s.margin, closeTo(4100 / 19500, 1e-9));
    expect(s.averageBasket, 9750);
    expect(s.quantity, 5);

    final prev = await r.summary(range.previous);
    expect(prev.transactions, 1);
    expect(prev.revenue, 7000);
    expect(growth(s.revenue, prev.revenue), closeTo(12500 / 7000, 1e-9));
  });

  test('harian berisi hari kosong, per jam dan per hari', () async {
    await seedSales();
    final r = repo();
    final week = ReportRange.preset(RangePreset.last7, at(0, 20));
    final days = await r.daily(week);
    expect(days, hasLength(7));
    expect(days.last.date, today);
    expect(days.last.revenue, 19500);
    expect(days[5].revenue, 7000); // kemarin
    expect(days.first.revenue, 0);

    final hours = await r.byHour(week);
    expect(hours, hasLength(24));
    expect(hours[9].transactions, 1);
    expect(hours[10].transactions, 1);
    expect(hours[14].revenue, 10500);

    final weekdays = await r.byWeekday(week);
    expect(weekdays[4].transactions, 2); // Kamis
    expect(weekdays[3].transactions, 1); // Rabu
  });

  test('produk dengan kelas ABC, kategori', () async {
    await seedSales();
    final r = repo();
    final week = ReportRange.preset(RangePreset.last7, at(0, 20));
    final list = await r.products(week);
    final indomie = list.firstWhere((p) => p.code == 'BRG001');
    expect(indomie.quantity, 5);
    expect(indomie.revenue, 17500);
    expect(indomie.grossProfit, 3500);
    expect(indomie.category, 'Makanan');
    // Laba: Indomie 3.500, Teh 1.300, Aqua 700 → Indomie A.
    expect(indomie.abc, AbcClass.a);
    expect(list.firstWhere((p) => p.code == 'BRG009').abc, isNot(AbcClass.a));

    final cats = await r.categories(week);
    expect(cats.map((c) => c.name), ['Makanan', 'Minuman']);
    expect(cats.first.revenue, 17500);
  });

  test('metode bayar, kasir, terminal', () async {
    await seedSales();
    final r = repo();
    final week = ReportRange.preset(RangePreset.last7, at(0, 20));

    final pays = {for (final p in await r.payments(week)) p.name: p};
    expect(pays['Tunai']!.transactions, 2);
    expect(pays['QRIS']!.revenue, 9000);

    expect((await r.cashiers(week)).single.name, 'Kasir Satu');
    expect((await r.terminals(week)).single.name, 'K01');
  });

  test('stok: nilai persediaan, perkiraan habis, terakhir terjual', () async {
    await seedSales();
    final r = repo();
    final inv = await r.inventory();
    expect(inv.products, 20);
    expect(inv.costValue, greaterThan(0));

    final status = {for (final s in await r.stockStatus()) s.code: s};
    final indomie = status['BRG001']!;
    expect(indomie.stock, 115);
    expect(indomie.averageDailySales, closeTo(5 / 30, 1e-9));
    expect(indomie.daysOfCover, closeTo(115 / (5 / 30), 1e-6));
    expect(indomie.lastSold, at(0, 14, 30));
    expect(status['BRG005']!.lastSold, isNull);
    expect(status['BRG005']!.daysOfCover, isNull);
  });

  test('dashboard ikut berubah saat ada transaksi baru', () async {
    final r = repo();
    final range = ReportRange.preset(RangePreset.today, at(0, 20));
    final values = <int>[];
    final sub = r.watchSummary(range).listen((s) => values.add(s.revenue));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sell(at(0, 11), {'BRG009': 2});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(values.first, 0);
    expect(values.last, 7000);
  });

  group('rentang', () {
    test('preset dan periode sebelumnya', () {
      final now = DateTime(2026, 10, 15, 13);
      final week = ReportRange.preset(RangePreset.last7, now);
      expect(week.start, DateTime(2026, 10, 9));
      expect(week.end, DateTime(2026, 10, 16));
      expect(week.days, 7);
      expect(week.previous.start, DateTime(2026, 10, 2));
      expect(week.previous.end, DateTime(2026, 10, 9));
      final month = ReportRange.preset(RangePreset.thisMonth, now);
      expect(month.start, DateTime(2026, 10, 1));
      expect(month.days, 15);
      final custom = ReportRange.days(
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 1),
      );
      expect(custom.start, DateTime(2026, 10, 1));
      expect(custom.days, 5);
    });

    test('ABC: laba nol/negatif selalu C', () {
      final list = classifyAbc(const [
        ProductPerformance(
          productId: 1,
          code: 'A',
          name: 'A',
          revenue: 100,
          cost: 20,
        ),
        ProductPerformance(
          productId: 2,
          code: 'B',
          name: 'B',
          revenue: 10,
          cost: 5,
        ),
        ProductPerformance(
          productId: 3,
          code: 'C',
          name: 'C',
          revenue: 10,
          cost: 15,
        ),
      ]);
      expect(
        {for (final p in list) p.code: p.abc},
        {'A': AbcClass.a, 'B': AbcClass.b, 'C': AbcClass.c},
      );
    });
  });

  test('export Excel berisi semua sheet dengan angka yang sama', () async {
    await seedSales();
    final r = repo();
    final week = ReportRange.preset(RangePreset.last7, at(0, 20));
    final bytes = exportReportXlsx(
      bundle: await r.bundle(week),
      inventory: await r.inventory(),
      stock: await r.stockStatus(),
      invoices: await SalesRepository(db)
          .watchBetween(week.start, week.end)
          .first,
    );
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, [
      'Ringkasan',
      'Harian',
      'Per Jam',
      'Per Hari',
      'Produk',
      'Kategori',
      'Pembayaran',
      'Kasir',
      'Terminal',
      'Stok',
      'Faktur',
    ]);
    String cell(String sheet, int row, int col) =>
        book.tables[sheet]!.rows[row][col]?.value.toString() ?? '';
    expect(cell('Ringkasan', 4, 0), 'Omzet bersih');
    expect(cell('Ringkasan', 4, 1), '26500'); // 7.000 + 19.500
    expect(book.tables['Faktur']!.rows, hasLength(4)); // judul + 3 faktur
    expect(book.tables['Harian']!.rows, hasLength(8)); // judul + 7 hari
  });
}
