import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/daos/reports_dao.dart';
import '../domain/report_models.dart';

/// Laporan keuangan dan penjualan. Metode `watch*` untuk dashboard (otomatis
/// terbarui setiap ada transaksi), metode lain dibaca sekali.
class ReportRepository {
  ReportRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  ReportsDao get _dao => _db.reportsDao;

  // SUM() di SQLite bisa berupa INTEGER atau REAL tergantung datanya (mis.
  // qty desimal), jadi dibaca dari data mentah sebagai `num`.
  static int _int(QueryRow r, String c) => (r.data[c] as num?)?.round() ?? 0;
  static double _double(QueryRow r, String c) =>
      (r.data[c] as num?)?.toDouble() ?? 0;

  // ---------------------------------------------------------------------------
  // Ringkasan & tren
  // ---------------------------------------------------------------------------

  SalesSummary _summary(QueryRow r) => SalesSummary(
    transactions: _int(r, 'tx'),
    revenue: _int(r, 'revenue'),
    grossSales: _int(r, 'gross'),
    discount: _int(r, 'discount'),
    cost: _int(r, 'cost'),
    quantity: _double(r, 'qty'),
  );

  Future<SalesSummary> summary(ReportRange range) async =>
      _summary(await _dao.summary(range.start, range.end).getSingle());

  Stream<SalesSummary> watchSummary(ReportRange range) =>
      _dao.summary(range.start, range.end).watchSingle().map(_summary);

  List<DailyPoint> _daily(ReportRange range, List<QueryRow> rows) {
    final byDay = {for (final r in rows) r.read<String>('day'): r};
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return [
      for (final d in range.dates)
        if (byDay[key(d)] case final r?)
          DailyPoint(
            date: d,
            transactions: _int(r, 'tx'),
            revenue: _int(r, 'revenue'),
            cost: _int(r, 'cost'),
          )
        else
          DailyPoint(date: d),
    ];
  }

  /// Satu titik per hari, termasuk hari tanpa penjualan (nol).
  Future<List<DailyPoint>> daily(ReportRange range) async =>
      _daily(range, await _dao.daily(range.start, range.end).get());

  Stream<List<DailyPoint>> watchDaily(ReportRange range) => _dao
      .daily(range.start, range.end)
      .watch()
      .map((rows) => _daily(range, rows));

  Future<List<BucketPoint>> _buckets(
    ReportRange range,
    String format,
    int count,
  ) async {
    final rows = await _dao.buckets(range.start, range.end, format).get();
    final byBucket = {for (final r in rows) _int(r, 'bucket'): r};
    return [
      for (var b = 0; b < count; b++)
        BucketPoint(
          bucket: b,
          transactions: byBucket[b] == null ? 0 : _int(byBucket[b]!, 'tx'),
          revenue: byBucket[b] == null ? 0 : _int(byBucket[b]!, 'revenue'),
        ),
    ];
  }

  /// 24 titik, jam 0–23.
  Future<List<BucketPoint>> byHour(ReportRange range) =>
      _buckets(range, '%H', 24);

  /// 7 titik, 0 = Minggu … 6 = Sabtu.
  Future<List<BucketPoint>> byWeekday(ReportRange range) =>
      _buckets(range, '%w', 7);

  // ---------------------------------------------------------------------------
  // Produk & kategori
  // ---------------------------------------------------------------------------

  ProductPerformance _product(QueryRow r) => ProductPerformance(
    productId: _int(r, 'product_id'),
    code: r.read<String?>('code') ?? '',
    name: r.read<String?>('name') ?? '',
    unit: r.read<String?>('unit'),
    category: r.read<String?>('category'),
    quantity: _double(r, 'qty'),
    revenue: _int(r, 'revenue'),
    cost: _int(r, 'cost'),
    transactions: _int(r, 'tx'),
  );

  /// Semua barang terjual dalam periode, sudah diberi kelas ABC.
  Future<List<ProductPerformance>> products(ReportRange range) async {
    final rows = await _dao.productSales(range.start, range.end).get();
    return classifyAbc(rows.map(_product).toList());
  }

  /// Terlaris menurut jumlah (untuk dashboard).
  Stream<List<ProductPerformance>> watchTopProducts(
    ReportRange range, {
    int limit = 5,
  }) => _dao
      .productSales(range.start, range.end, limit: limit)
      .watch()
      .map((rows) => rows.map(_product).toList());

  GroupPerformance _group(QueryRow r) => GroupPerformance(
    name: r.read<String?>('grp') ?? '–',
    transactions: _int(r, 'tx'),
    revenue: _int(r, 'revenue'),
    cost: _int(r, 'cost'),
    discount: r.data.containsKey('discount') ? _int(r, 'discount') : 0,
    quantity: r.data.containsKey('qty') ? _double(r, 'qty') : 0,
  );

  Future<List<GroupPerformance>> _groups(Selectable<QueryRow> q) async =>
      (await q.get()).map(_group).toList();

  Future<List<GroupPerformance>> categories(ReportRange range) =>
      _groups(_dao.categorySales(range.start, range.end));

  Future<List<GroupPerformance>> payments(ReportRange range) =>
      _groups(_dao.paymentSales(range.start, range.end));

  Future<List<GroupPerformance>> vouchers(ReportRange range) =>
      _groups(_dao.voucherSales(range.start, range.end));

  Future<List<GroupPerformance>> cashiers(ReportRange range) =>
      _groups(_dao.cashierSales(range.start, range.end));

  Future<List<GroupPerformance>> terminals(ReportRange range) =>
      _groups(_dao.terminalSales(range.start, range.end));

  /// Semua bagian laporan untuk [range] (dimuat paralel).
  Future<ReportBundle> bundle(ReportRange range) async {
    final results = await Future.wait<Object>([
      summary(range),
      summary(range.previous),
      daily(range),
      byHour(range),
      byWeekday(range),
      products(range),
      categories(range),
      payments(range),
      vouchers(range),
      cashiers(range),
      terminals(range),
    ]);
    return ReportBundle(
      range: range,
      summary: results[0] as SalesSummary,
      previous: results[1] as SalesSummary,
      daily: results[2] as List<DailyPoint>,
      byHour: results[3] as List<BucketPoint>,
      byWeekday: results[4] as List<BucketPoint>,
      products: results[5] as List<ProductPerformance>,
      categories: results[6] as List<GroupPerformance>,
      payments: results[7] as List<GroupPerformance>,
      vouchers: results[8] as List<GroupPerformance>,
      cashiers: results[9] as List<GroupPerformance>,
      terminals: results[10] as List<GroupPerformance>,
    );
  }

  // ---------------------------------------------------------------------------
  // Stok
  // ---------------------------------------------------------------------------

  InventorySummary _inventory(QueryRow r) => InventorySummary(
    products: _int(r, 'products'),
    costValue: _int(r, 'cost_value'),
    retailValue: _int(r, 'retail_value'),
  );

  Future<InventorySummary> inventory() async =>
      _inventory(await _dao.inventory().getSingle());

  /// Rata-rata penjualan dihitung dari [windowDays] hari terakhir.
  static const windowDays = 30;

  /// Kondisi stok semua barang aktif.
  Future<List<StockStatus>> stockStatus() async {
    final now = _clock();
    final since = DateTime(now.year, now.month, now.day - windowDays + 1);
    final rows = await _dao.stockStatus(since).get();
    return [
      for (final r in rows)
        StockStatus(
          productId: _int(r, 'id'),
          code: r.read<String>('code'),
          name: r.read<String>('name'),
          unit: r.read<String?>('unit'),
          stock: _double(r, 'stock'),
          purchasePrice: _int(r, 'purchase_price'),
          averageDailySales: _double(r, 'recent_qty') / windowDays,
          lastSold: r.read<int?>('last_sold') == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  r.read<int>('last_sold') * 1000,
                ),
        ),
    ];
  }
}

final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => ReportRepository(ref.watch(appDatabaseProvider)),
);
