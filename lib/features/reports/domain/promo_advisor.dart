import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';

/// Barang (ringkas) untuk saran promo.
@immutable
class PromoItem {
  const PromoItem({
    required this.productId,
    required this.code,
    required this.name,
    this.unit,
    required this.price,
    this.purchasePrice = 0,
  });

  final int productId;
  final String code;
  final String name;
  final String? unit;

  /// Harga jual (toko yang dilihat, atau default).
  final int price;

  /// 0 = belum diisi.
  final int purchasePrice;
}

/// Barang yang mungkin lambat laku.
@immutable
class SlowItem {
  const SlowItem({
    required this.item,
    required this.stock,
    required this.soldQty,
    this.lastSold,
    this.createdAt,
  });

  final PromoItem item;
  final double stock;

  /// Terjual (satuan dasar) dalam [PromoAdvisor.slowDays] hari.
  final double soldQty;
  final DateTime? lastSold;
  final DateTime? createdAt;
}

/// Dua barang yang dibeli dalam faktur yang sama.
@immutable
class PairStat {
  const PairStat({
    required this.a,
    required this.b,
    required this.together,
    required this.countA,
    required this.countB,
  });

  final PromoItem a;
  final PromoItem b;

  /// Jumlah faktur yang berisi keduanya.
  final int together;

  /// Jumlah faktur berisi [a] / [b].
  final int countA;
  final int countB;
}

/// Barang yang paling sering dibeli.
@immutable
class TrafficItem {
  const TrafficItem({
    required this.item,
    required this.transactions,
    required this.revenue,
    required this.cost,
  });

  final PromoItem item;
  final int transactions;
  final int revenue;
  final int cost;
}

/// Bahan analisa (dari database, lihat `PromoRepository`).
@immutable
class PromoInput {
  const PromoInput({
    required this.now,
    this.slow = const [],
    this.pairs = const [],
    this.pairTransactions = 0,
    this.baskets = const [],
    this.margin,
    this.hourly = const {},
    this.traffic = const [],
  });

  final DateTime now;
  final List<SlowItem> slow;
  final List<PairStat> pairs;

  /// Jumlah faktur dalam rentang analisa pasangan.
  final int pairTransactions;

  /// Total tiap faktur penjualan [PromoAdvisor.basketDays] hari terakhir.
  final List<int> baskets;

  /// Margin laba kotor (0–1) rentang yang sama; `null` = tidak diketahui.
  final double? margin;

  /// Omzet per jam (0–23), [PromoAdvisor.basketDays] hari terakhir.
  final Map<int, int> hourly;
  final List<TrafficItem> traffic;
}

enum PromoKind {
  clearance('Cuci gudang'),
  bundle('Paket hemat'),
  basket('Naikkan nilai belanja'),
  quietHours('Jam sepi'),
  traffic('Barang umpan');

  const PromoKind(this.label);

  final String label;
}

/// Voucher yang disarankan (diisi ke form Voucher Baru).
@immutable
class VoucherIdea {
  const VoucherIdea({
    required this.code,
    required this.name,
    required this.amount,
    required this.minPurchase,
    required this.days,
  });

  final String code;
  final String name;
  final int amount;
  final int minPurchase;

  /// Masa berlaku sejak hari ini.
  final int days;
}

@immutable
class PromoSuggestion {
  const PromoSuggestion({
    required this.kind,
    required this.title,
    required this.detail,
    required this.reason,
    this.productIds = const [],
    this.voucher,
  });

  final PromoKind kind;
  final String title;

  /// Apa yang disarankan.
  final String detail;

  /// Dasar angka (kenapa).
  final String reason;

  /// Barang terkait (tombol "Ubah Harga" membuka barang pertama).
  final List<int> productIds;
  final VoucherIdea? voucher;
}

/// Saran promo dari data penjualan & stok. Fungsi murni.
abstract final class PromoAdvisor {
  static const slowDays = 60;
  static const pairDays = 90;
  static const basketDays = 30;

  /// Barang baru (umur < ini) tidak disarankan cuci gudang.
  static const newItemDays = 30;

  /// Persediaan lebih lama dari ini (hari) = lambat laku.
  static const slowCoverDays = 120;

  static int _down(num v, int step) => (v / step).floor() * step;
  static int _up(num v, int step) => (v / step).ceil() * step;

  static String _pct(double v) => '${Fmt.number((v * 100).round())}%';

  static List<PromoSuggestion> suggest(PromoInput input) => [
    ..._clearance(input),
    ..._bundles(input),
    ?_basket(input),
    ?_quietHours(input),
    ..._traffic(input),
  ];

  static List<PromoSuggestion> _clearance(PromoInput input) {
    final candidates = <(SlowItem, int)>[];
    for (final s in input.slow) {
      if (s.stock <= 0 || s.item.price <= 0) continue;
      final age = s.createdAt == null
          ? null
          : input.now.difference(s.createdAt!).inDays;
      if (age != null && age < newItemDays) continue;
      final perDay = s.soldQty / slowDays;
      final cover = perDay > 0 ? s.stock / perDay : double.infinity;
      if (cover <= slowCoverDays) continue;
      final unitValue = s.item.purchasePrice > 0
          ? s.item.purchasePrice
          : s.item.price;
      candidates.add((s, (s.stock * unitValue).round()));
    }
    candidates.sort((a, b) => b.$2.compareTo(a.$2));
    return [
      for (final (s, value) in candidates.take(8))
        _clearanceFor(s, value, input.now),
    ];
  }

  static PromoSuggestion _clearanceFor(SlowItem s, int value, DateTime now) {
    final i = s.item;
    // Diskon ±15%, tetapi harga tidak di bawah harga beli + 2%.
    var target = _down(i.price * 0.85, 100);
    if (i.purchasePrice > 0) {
      final floor = _up(i.purchasePrice * 1.02, 100);
      if (target < floor) target = floor;
    }
    final last = s.lastSold == null
        ? 'belum pernah terjual'
        : 'terakhir terjual ${now.difference(s.lastSold!).inDays} hari lalu';
    final detail = target < i.price
        ? 'Turunkan harga ke ${Fmt.rupiah(target)} '
              '(−${_pct(1 - target / i.price)}), pajang di depan, atau '
              'jadikan bonus pembelian barang laris.'
        : 'Harga sudah mepet harga beli: jadikan bonus/paket dengan barang '
              'laris, atau tukar ke pemasok.';
    return PromoSuggestion(
      kind: PromoKind.clearance,
      title: i.name,
      detail: detail,
      reason:
          'Stok ${'${Fmt.number(s.stock)} ${i.unit ?? ''}'.trimRight()}, '
          'terjual ${Fmt.number(s.soldQty)} dalam $slowDays hari, $last. '
          'Modal tertahan ±${Fmt.rupiah(value)}.',
      productIds: [i.productId],
    );
  }

  static List<PromoSuggestion> _bundles(PromoInput input) {
    final n = input.pairTransactions;
    if (n < 10) return const [];
    final scored = <(PairStat, double)>[];
    for (final p in input.pairs) {
      if (p.together < 3 || p.countA == 0 || p.countB == 0) continue;
      final lift = p.together * n / (p.countA * p.countB);
      if (lift < 1.2) continue;
      scored.add((p, lift));
    }
    scored.sort((a, b) {
      final t = b.$1.together.compareTo(a.$1.together);
      return t != 0 ? t : b.$2.compareTo(a.$2);
    });
    return [for (final (p, lift) in scored.take(5)) _bundleFor(p, lift)];
  }

  static PromoSuggestion _bundleFor(PairStat p, double lift) {
    final normal = p.a.price + p.b.price;
    final cost = p.a.purchasePrice + p.b.purchasePrice;
    var price = _down(normal * 0.95, normal >= 20000 ? 500 : 100);
    if (cost > 0 && price < cost * 1.05) price = _up(cost * 1.05, 100);
    final share = p.together / math.min(p.countA, p.countB);
    return PromoSuggestion(
      kind: PromoKind.bundle,
      title: '${p.a.name} + ${p.b.name}',
      detail: price < normal
          ? 'Jual sebagai paket ${Fmt.rupiah(price)} (normal '
                '${Fmt.rupiah(normal)}, hemat ${Fmt.rupiah(normal - price)}). '
                'Taruh berdekatan di rak.'
          : 'Taruh berdekatan di rak / tawarkan bersamaan di kasir.',
      reason:
          'Dibeli bersamaan di ${p.together} transaksi '
          '(${_pct(share)} dari pembeli salah satunya), '
          '${lift.toStringAsFixed(1).replaceAll('.', ',')}× lebih sering '
          'dari kebetulan.',
      productIds: [p.a.productId, p.b.productId],
    );
  }

  static PromoSuggestion? _basket(PromoInput input) {
    final list = [...input.baskets.where((v) => v > 0)]..sort();
    if (list.length < 20) return null;
    int at(double q) => list[((list.length - 1) * q).round()];
    final median = at(0.5);
    final p75 = at(0.75);
    final avg = list.reduce((a, b) => a + b) / list.length;
    final step = median >= 100000 ? 10000 : 5000;
    var min = _up(math.max(p75, median * 1.25), step);
    if (min <= median) min = median + step;
    // Potongan ±5% dari min. belanja, maksimal 40% dari laba kotornya.
    var amount = _down(min * 0.05, 500);
    if (input.margin case final m? when m > 0) {
      amount = math.min(amount, _down(min * m * 0.4, 500));
    }
    if (amount < 500) return null;
    final code = 'BELANJA${(min / 1000).round()}K';
    return PromoSuggestion(
      kind: PromoKind.basket,
      title: 'Belanja min. ${Fmt.rupiah(min)} hemat ${Fmt.rupiah(amount)}',
      detail:
          'Buat voucher $code berlaku 14 hari. Kasir menawarkannya saat '
          'belanja pelanggan mendekati ${Fmt.rupiah(min)}.',
      reason:
          'Dari ${list.length} transaksi $basketDays hari terakhir: rata-rata '
          '${Fmt.rupiah(avg.round())}, separuh di bawah ${Fmt.rupiah(median)}, '
          '75% di bawah ${Fmt.rupiah(p75)}'
          '${input.margin == null ? '' : ', margin ${_pct(input.margin!)}'}.',
      voucher: VoucherIdea(
        code: code,
        name: 'Belanja min. ${Fmt.rupiah(min)} hemat ${Fmt.rupiah(amount)}',
        amount: amount,
        minPurchase: min,
        days: 14,
      ),
    );
  }

  static PromoSuggestion? _quietHours(PromoInput input) {
    final hours = input.hourly.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    if (hours.length < 6) return null;
    final open = hours.first.key;
    final close = hours.last.key;
    final total = hours.fold(0, (s, e) => s + e.value);
    final avg = total / (close - open + 1);
    // Jam buka (antara jam pertama & terakhir) yang omzetnya < 40%.
    final quiet = <int>[
      for (var h = open; h <= close; h++)
        if ((input.hourly[h] ?? 0) < avg * 0.4) h,
    ];
    if (quiet.isEmpty) return null;
    // Rentang berurutan terpanjang.
    var best = <int>[];
    var run = <int>[];
    for (final h in quiet) {
      if (run.isNotEmpty && h != run.last + 1) run = [];
      run.add(h);
      if (run.length > best.length) best = [...run];
    }
    final revenue = best.fold(0, (s, h) => s + (input.hourly[h] ?? 0));
    final share = revenue / (avg * best.length);
    String hh(int h) => '${h.toString().padLeft(2, '0')}.00';
    return PromoSuggestion(
      kind: PromoKind.quietHours,
      title: 'Promo jam ${hh(best.first)}–${hh(best.last + 1)}',
      detail:
          'Coba diskon kecil / bonus khusus jam ini (umumkan di WhatsApp '
          'atau papan depan toko) supaya pembeli datang di jam sepi.',
      reason:
          'Omzet jam ini hanya ±${_pct(share)} dari rata-rata jam buka '
          'lain ($basketDays hari terakhir).',
    );
  }

  static List<PromoSuggestion> _traffic(PromoInput input) {
    final picks = [
      for (final t in input.traffic)
        if (t.transactions >= 10 &&
            t.revenue > 0 &&
            t.cost > 0 &&
            (t.revenue - t.cost) / t.revenue >= 0.2)
          t,
    ]..sort((a, b) => b.transactions.compareTo(a.transactions));
    return [
      for (final t in picks.take(3))
        PromoSuggestion(
          kind: PromoKind.traffic,
          title: t.item.name,
          detail:
              'Diskon kecil (mis. ${Fmt.rupiah(math.max(100, _down(t.item.price * 0.05, 100)))}) '
              'untuk barang ini bisa menarik pembeli, lalu mereka belanja '
              'barang lain.',
          reason:
              'Dibeli di ${t.transactions} transaksi $basketDays hari '
              'terakhir, margin '
              '${_pct((t.revenue - t.cost) / t.revenue)}.',
          productIds: [t.item.productId],
        ),
    ];
  }
}

/// Promo yang dijalankan dari Saran Promo dan hasilnya: penjualan per hari
/// sebelum ([PromoResult.window] hari) vs sesudah dijalankan.
@immutable
class PromoResult {
  const PromoResult({
    required this.kind,
    required this.title,
    required this.at,
    required this.daysAfter,
    this.voucherCode,
    this.qtyBefore = 0,
    this.qtyAfter = 0,
    this.revenueBefore = 0,
    this.revenueAfter = 0,
    this.uses = 0,
    this.discount = 0,
    this.basketBefore,
    this.basketAfter,
  });

  /// Pembanding sebelum promo (hari).
  static const window = 14;

  final PromoKind kind;
  final String title;
  final DateTime at;

  /// Lama berjalan (hari, minimal 1).
  final int daysAfter;
  final String? voucherCode;

  /// Barang: terjual (satuan dasar) & omzet sebelum / sesudah.
  final double qtyBefore;
  final double qtyAfter;
  final int revenueBefore;
  final int revenueAfter;

  /// Voucher: dipakai berapa kali, total potongan, rata-rata belanja.
  final int uses;
  final int discount;
  final int? basketBefore;
  final int? basketAfter;

  bool get isVoucher => voucherCode != null;
  double get perDayBefore => qtyBefore / window;
  double get perDayAfter => qtyAfter / daysAfter;

  /// Perubahan laku per hari (0,5 = +50%); `null` bila sebelumnya 0.
  double? get change =>
      perDayBefore == 0 ? null : perDayAfter / perDayBefore - 1;
}
