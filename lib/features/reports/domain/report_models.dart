import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';

enum RangePreset {
  today('Hari Ini'),
  last7('7 Hari'),
  last30('30 Hari'),
  thisMonth('Bulan Ini'),
  custom('Pilih Tanggal');

  const RangePreset(this.label);

  final String label;
}

/// Rentang tanggal laporan [start, end) dalam waktu lokal, per hari penuh.
@immutable
class ReportRange {
  const ReportRange(this.start, this.end);

  final DateTime start;

  /// Eksklusif (awal hari setelah hari terakhir).
  final DateTime end;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  factory ReportRange.preset(RangePreset preset, DateTime now) {
    final today = _day(now);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    return switch (preset) {
      RangePreset.today => ReportRange(today, tomorrow),
      RangePreset.last7 => ReportRange(
        DateTime(today.year, today.month, today.day - 6),
        tomorrow,
      ),
      RangePreset.last30 => ReportRange(
        DateTime(today.year, today.month, today.day - 29),
        tomorrow,
      ),
      RangePreset.thisMonth => ReportRange(
        DateTime(today.year, today.month),
        tomorrow,
      ),
      RangePreset.custom => ReportRange(today, tomorrow),
    };
  }

  /// Dari tanggal [from] s.d. [to] (keduanya termasuk).
  factory ReportRange.days(DateTime from, DateTime to) {
    final a = _day(from), b = _day(to);
    final first = a.isBefore(b) ? a : b;
    final last = a.isBefore(b) ? b : a;
    return ReportRange(first, DateTime(last.year, last.month, last.day + 1));
  }

  /// Jumlah hari dalam rentang (aman terhadap pergantian jam musim panas).
  int get days => DateTime.utc(
    end.year,
    end.month,
    end.day,
  ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;

  /// Periode sebelumnya dengan panjang sama, untuk perbandingan.
  ReportRange get previous =>
      ReportRange(DateTime(start.year, start.month, start.day - days), start);

  /// Setiap tanggal di dalam rentang.
  List<DateTime> get dates => [
    for (var i = 0; i < days; i++)
      DateTime(start.year, start.month, start.day + i),
  ];

  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  String get label => days == 1
      ? Fmt.dateShort(start)
      : '${Fmt.dateShort(start)} – ${Fmt.dateShort(lastDay)}';

  @override
  bool operator ==(Object other) =>
      other is ReportRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Ringkasan keuangan satu periode.
@immutable
class SalesSummary {
  const SalesSummary({
    this.transactions = 0,
    this.revenue = 0,
    this.grossSales = 0,
    this.discount = 0,
    this.cost = 0,
    this.quantity = 0,
  });

  final int transactions;

  /// Omzet bersih (setelah potongan) = uang yang diterima.
  final int revenue;

  /// Sebelum potongan (potongan hanya ada di faktur lama).
  final int grossSales;
  final int discount;

  /// Harga pokok barang terjual (qty × harga beli saat terjual).
  final int cost;
  final double quantity;

  int get grossProfit => revenue - cost;

  /// Margin laba kotor terhadap omzet (0–1). `null` jika belum ada omzet.
  double? get margin => revenue == 0 ? null : grossProfit / revenue;

  /// Rata-rata belanja per transaksi.
  int get averageBasket =>
      transactions == 0 ? 0 : (revenue / transactions).round();

  double get itemsPerTransaction =>
      transactions == 0 ? 0 : quantity / transactions;
}

/// Perubahan dibanding periode sebelumnya (0,12 = naik 12%). `null` jika
/// periode sebelumnya nol (tidak bisa dibandingkan).
double? growth(num current, num previous) =>
    previous == 0 ? null : (current - previous) / previous;

@immutable
class DailyPoint {
  const DailyPoint({
    required this.date,
    this.transactions = 0,
    this.revenue = 0,
    this.cost = 0,
  });

  final DateTime date;
  final int transactions;
  final int revenue;
  final int cost;

  int get grossProfit => revenue - cost;
}

/// Penjualan per jam (0–23) atau per hari dalam seminggu (0 = Minggu).
@immutable
class BucketPoint {
  const BucketPoint({
    required this.bucket,
    this.transactions = 0,
    this.revenue = 0,
  });

  final int bucket;
  final int transactions;
  final int revenue;
}

enum AbcClass {
  a('A', 'Penyumbang utama (±80% laba)'),
  b('B', 'Penyumbang menengah (±15% laba)'),
  c('C', 'Penyumbang kecil (±5% laba)');

  const AbcClass(this.label, this.description);

  final String label;
  final String description;
}

/// Kinerja satu barang dalam periode.
@immutable
class ProductPerformance {
  const ProductPerformance({
    required this.productId,
    required this.code,
    required this.name,
    this.category,
    this.unit,
    this.quantity = 0,
    this.revenue = 0,
    this.cost = 0,
    this.transactions = 0,
    this.abc,
  });

  final int productId;
  final String code;
  final String name;
  final String? category;
  final String? unit;
  final double quantity;

  /// Total baris faktur.
  final int revenue;
  final int cost;
  final int transactions;
  final AbcClass? abc;

  int get grossProfit => revenue - cost;
  double? get margin => revenue == 0 ? null : grossProfit / revenue;

  ProductPerformance withAbc(AbcClass c) => ProductPerformance(
    productId: productId,
    code: code,
    name: name,
    category: category,
    unit: unit,
    quantity: quantity,
    revenue: revenue,
    cost: cost,
    transactions: transactions,
    abc: c,
  );
}

/// Klasifikasi ABC (Pareto) berdasarkan laba kotor: urut dari laba terbesar,
/// kumulatif s.d. 80% = A, s.d. 95% = B, sisanya C. Barang yang rugi/nol = C.
List<ProductPerformance> classifyAbc(List<ProductPerformance> items) {
  final sorted = [...items]
    ..sort((a, b) => b.grossProfit.compareTo(a.grossProfit));
  final totalProfit = sorted
      .where((p) => p.grossProfit > 0)
      .fold<int>(0, (s, p) => s + p.grossProfit);

  final result = <ProductPerformance>[];
  var cumulative = 0;
  for (final p in sorted) {
    if (p.grossProfit <= 0 || totalProfit == 0) {
      result.add(p.withAbc(AbcClass.c));
      continue;
    }
    // Kelas ditentukan oleh porsi kumulatif SEBELUM barang ini, sehingga
    // barang yang melewati batas 80% tetap masuk A.
    final before = cumulative / totalProfit;
    cumulative += p.grossProfit;
    result.add(
      p.withAbc(
        before < 0.8
            ? AbcClass.a
            : before < 0.95
            ? AbcClass.b
            : AbcClass.c,
      ),
    );
  }
  return result;
}

/// Pengelompokan umum (kategori, metode bayar, kasir, terminal).
@immutable
class GroupPerformance {
  const GroupPerformance({
    required this.name,
    this.transactions = 0,
    this.revenue = 0,
    this.cost = 0,
    this.discount = 0,
    this.quantity = 0,
  });

  final String name;
  final int transactions;
  final int revenue;
  final int cost;

  /// Total potongan faktur dalam kelompok ini.
  final int discount;
  final double quantity;

  int get grossProfit => revenue - cost;
  double? get margin => revenue == 0 ? null : grossProfit / revenue;
  int get averageBasket =>
      transactions == 0 ? 0 : (revenue / transactions).round();
}

/// Kondisi stok satu barang untuk laporan stok.
@immutable
class StockStatus {
  const StockStatus({
    required this.productId,
    required this.code,
    required this.name,
    this.unit,
    required this.stock,
    required this.purchasePrice,
    required this.averageDailySales,
    this.lastSold,
  });

  final int productId;
  final String code;
  final String name;
  final String? unit;
  final double stock;
  final int purchasePrice;

  /// Rata-rata terjual per hari (30 hari terakhir).
  final double averageDailySales;
  final DateTime? lastSold;

  /// Modal yang tertahan di barang ini.
  int get value => stock <= 0 ? 0 : (stock * purchasePrice).round();

  /// Perkiraan berapa hari lagi stok habis. `null` jika tidak ada penjualan.
  double? get daysOfCover => averageDailySales <= 0
      ? null
      : (stock <= 0 ? 0 : stock / averageDailySales);
}

@immutable
class InventorySummary {
  const InventorySummary({
    this.products = 0,
    this.costValue = 0,
    this.retailValue = 0,
  });

  /// Barang aktif yang stoknya > 0.
  final int products;

  /// Σ stok × harga beli (modal tertahan).
  final int costValue;

  /// Σ stok × harga jual (potensi omzet).
  final int retailValue;
}

/// Semua data laporan untuk satu rentang, dimuat sekaligus supaya setiap
/// bagian halaman Laporan dan file export memakai angka yang sama.
@immutable
class ReportBundle {
  const ReportBundle({
    required this.range,
    required this.summary,
    required this.previous,
    required this.daily,
    required this.byHour,
    required this.byWeekday,
    required this.products,
    required this.categories,
    required this.payments,
    required this.cashiers,
    required this.terminals,
  });

  final ReportRange range;
  final SalesSummary summary;

  /// Ringkasan periode sebelumnya dengan panjang sama.
  final SalesSummary previous;
  final List<DailyPoint> daily;
  final List<BucketPoint> byHour;
  final List<BucketPoint> byWeekday;
  final List<ProductPerformance> products;
  final List<GroupPerformance> categories;
  final List<GroupPerformance> payments;
  final List<GroupPerformance> cashiers;
  final List<GroupPerformance> terminals;

  /// Jam dengan omzet terbesar, atau `null` jika belum ada penjualan.
  BucketPoint? get busiestHour => _max(byHour);
  BucketPoint? get busiestWeekday => _max(byWeekday);

  static BucketPoint? _max(List<BucketPoint> list) {
    BucketPoint? best;
    for (final b in list) {
      if (b.revenue > 0 && (best == null || b.revenue > best.revenue)) best = b;
    }
    return best;
  }
}

const weekdayNames = [
  'Minggu',
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
];
