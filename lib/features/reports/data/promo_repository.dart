import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../stores/presentation/store_scope.dart';
import '../domain/promo_advisor.dart';

/// Mengumpulkan bahan [PromoAdvisor] dari database untuk toko [storeId]
/// (`null` = semua toko).
class PromoRepository {
  PromoRepository(this._db, {this.storeId, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final int? storeId;
  final DateTime Function() _clock;

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.fromMillisecondsSinceEpoch((v as int) * 1000);

  List<Variable<Object>> _vars(DateTime since) => [
    Variable.withDateTime(since),
    Variable<int>(storeId),
  ];

  /// Harga & stok toko `?2` (`NULL` = harga default, stok dijumlah).
  static const _price =
      'COALESCE((SELECT sp.selling_price FROM store_products sp '
      'WHERE sp.product_id = p.id AND sp.store_id = ?2), p.selling_price)';
  static const _stock =
      'COALESCE((SELECT SUM(sp.stock) FROM store_products sp '
      'WHERE sp.product_id = p.id AND (?2 IS NULL OR sp.store_id = ?2)), 0)';
  static const _store = '(?2 IS NULL OR s.store_id = ?2)';

  PromoItem _item(QueryRow r) => PromoItem(
    productId: r.read<int>('id'),
    code: r.read<String>('code'),
    name: r.read<String>('name'),
    unit: r.read<String?>('unit'),
    price: (r.data['price'] as num).toInt(),
    purchasePrice: (r.data['purchase_price'] as num).toInt(),
  );

  static const _itemCols =
      'p.id, p.code, p.name, u.name AS unit, p.purchase_price, '
      '$_price AS price';

  Future<Map<int, PromoItem>> _items(Iterable<int> ids) async {
    final list = ids.toSet().toList();
    if (list.isEmpty) return const {};
    final rows = await _db
        .customSelect(
          'SELECT $_itemCols FROM products p '
          'LEFT JOIN units u ON u.id = p.unit_id '
          'WHERE p.id IN (${List.filled(list.length, '?').join(', ')})',
          variables: [
            // ?1 tidak dipakai; ?2 = toko (dipakai _price).
            Variable.withInt(0),
            Variable<int>(storeId),
            for (final id in list) Variable.withInt(id),
          ],
        )
        .get();
    return {for (final r in rows) r.read<int>('id'): _item(r)};
  }

  DateTime _daysAgo(int days) {
    final now = _clock();
    return DateTime(now.year, now.month, now.day - days + 1);
  }

  Future<PromoInput> load() async {
    final now = _clock();

    final slowRows = await _db.customSelect('''
      SELECT $_itemCols, p.created_at, $_stock AS stock,
        COALESCE((SELECT SUM(si.qty * si.unit_factor) FROM sale_items si
          JOIN sales s ON s.id = si.sale_id
          WHERE si.product_id = p.id AND s.sale_date >= ?1 AND $_store), 0)
          AS sold,
        (SELECT MAX(s.sale_date) FROM sale_items si
          JOIN sales s ON s.id = si.sale_id
          WHERE si.product_id = p.id AND s.return_of_id IS NULL AND $_store)
          AS last_sold
      FROM products p LEFT JOIN units u ON u.id = p.unit_id
      WHERE p.is_active = 1
      ''', variables: _vars(_daysAgo(PromoAdvisor.slowDays))).get();

    final pairSince = _daysAgo(PromoAdvisor.pairDays);
    const items =
        'SELECT DISTINCT si.sale_id, si.product_id FROM sale_items si '
        'JOIN sales s ON s.id = si.sale_id WHERE s.return_of_id IS NULL '
        'AND s.sale_date >= ?1 AND $_store';
    final pairRows = await _db.customSelect('''
      WITH items AS ($items)
      SELECT a.product_id AS a, b.product_id AS b, COUNT(*) AS together,
        (SELECT COUNT(*) FROM items x WHERE x.product_id = a.product_id) AS ca,
        (SELECT COUNT(*) FROM items x WHERE x.product_id = b.product_id) AS cb
      FROM items a JOIN items b
        ON a.sale_id = b.sale_id AND a.product_id < b.product_id
      GROUP BY a.product_id, b.product_id
      HAVING COUNT(*) >= 3
      ORDER BY together DESC LIMIT 30
      ''', variables: _vars(pairSince)).get();
    final pairTx = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM sales s WHERE s.return_of_id IS NULL '
          'AND s.sale_date >= ?1 AND $_store',
          variables: _vars(pairSince),
        )
        .getSingle();

    final since = _daysAgo(PromoAdvisor.basketDays);
    final baskets = await _db
        .customSelect(
          'SELECT s.total FROM sales s WHERE s.return_of_id IS NULL '
          'AND s.sale_date >= ?1 AND $_store',
          variables: _vars(since),
        )
        .get();
    final money = await _db.customSelect('''
      SELECT (SELECT COALESCE(SUM(s.total), 0) FROM sales s
                WHERE s.sale_date >= ?1 AND $_store) AS revenue,
             (SELECT COALESCE(SUM(si.qty * si.purchase_price), 0)
                FROM sale_items si JOIN sales s ON s.id = si.sale_id
                WHERE s.sale_date >= ?1 AND $_store) AS cost,
             (SELECT COUNT(*) FROM sale_items si
                JOIN sales s ON s.id = si.sale_id
                WHERE s.sale_date >= ?1 AND $_store
                  AND si.purchase_price = 0) AS no_cost
      ''', variables: _vars(since)).getSingle();
    final hourly = await _db
        .customSelect(
          "SELECT CAST(strftime('%H', s.sale_date, 'unixepoch', 'localtime') "
          'AS INTEGER) AS h, SUM(s.total) AS revenue FROM sales s '
          'WHERE s.sale_date >= ?1 AND $_store GROUP BY h',
          variables: _vars(since),
        )
        .get();
    final trafficRows = await _db.customSelect('''
      SELECT si.product_id AS id,
        COUNT(DISTINCT CASE WHEN s.return_of_id IS NULL THEN si.sale_id END)
          AS tx,
        SUM(si.subtotal) AS revenue, SUM(si.qty * si.purchase_price) AS cost
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      WHERE s.sale_date >= ?1 AND $_store
      GROUP BY si.product_id ORDER BY tx DESC LIMIT 10
      ''', variables: _vars(since)).get();

    final refs = await _items([
      for (final r in pairRows) ...[r.read<int>('a'), r.read<int>('b')],
      for (final r in trafficRows) r.read<int>('id'),
    ]);
    final revenue = (money.data['revenue'] as num).toInt();
    final cost = (money.data['cost'] as num).toInt();

    return PromoInput(
      now: now,
      slow: [
        for (final r in slowRows)
          SlowItem(
            item: _item(r),
            stock: (r.data['stock'] as num).toDouble(),
            soldQty: (r.data['sold'] as num).toDouble(),
            lastSold: _date(r.data['last_sold']),
            createdAt: _date(r.data['created_at']),
          ),
      ],
      pairs: [
        for (final r in pairRows)
          if ((refs[r.read<int>('a')], refs[r.read<int>('b')]) case (
            final a?,
            final b?,
          ))
            PairStat(
              a: a,
              b: b,
              together: r.read<int>('together'),
              countA: r.read<int>('ca'),
              countB: r.read<int>('cb'),
            ),
      ],
      pairTransactions: pairTx.read<int>('n'),
      baskets: [for (final r in baskets) r.read<int>('total')],
      // Harga beli belum lengkap = margin tidak bisa dipercaya.
      margin: revenue > 0 && money.read<int>('no_cost') == 0
          ? (revenue - cost) / revenue
          : null,
      hourly: {
        for (final r in hourly)
          r.read<int>('h'): (r.data['revenue'] as num).toInt(),
      },
      traffic: [
        for (final r in trafficRows)
          if (refs[r.read<int>('id')] case final item?)
            TrafficItem(
              item: item,
              transactions: r.read<int>('tx'),
              revenue: (r.data['revenue'] as num).toInt(),
              cost: (r.data['cost'] as num).toInt(),
            ),
      ],
    );
  }

  Future<List<PromoSuggestion>> suggestions() async =>
      PromoAdvisor.suggest(await load());

  /// Mencatat promo yang dijalankan dari saran (untuk [results]).
  Future<void> record(
    PromoKind kind,
    String title, {
    int? productId,
    String? voucherCode,
  }) => _db
      .into(_db.promoActions)
      .insert(
        PromoActionsCompanion.insert(
          kind: kind.name,
          title: title,
          productId: Value(productId),
          voucherCode: Value(voucherCode),
          storeId: Value(storeId),
          createdAt: _clock(),
        ),
      );

  /// Hasil promo yang dijalankan [days] hari terakhir, terbaru dulu.
  Future<List<PromoResult>> results({int days = 90}) async {
    final now = _clock();
    final actions =
        await (_db.select(_db.promoActions)
              ..where(
                (a) => a.createdAt.isBiggerOrEqualValue(
                  now.subtract(Duration(days: days)),
                ),
              )
              ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
            .get();
    final kinds = PromoKind.values.asNameMap();
    final out = <PromoResult>[];
    for (final a in actions) {
      final kind = kinds[a.kind];
      if (kind == null) continue;
      final start = a.createdAt.subtract(
        const Duration(days: PromoResult.window),
      );
      final daysAfter = now.difference(a.createdAt).inHours ~/ 24 + 1;
      List<Variable<Object>> vars(DateTime from, DateTime to) => [
        Variable.withDateTime(from),
        Variable.withDateTime(to),
        Variable<int>(a.storeId),
      ];
      const store = '(?3 IS NULL OR s.store_id = ?3)';
      if (a.voucherCode case final code?) {
        final used = await _db
            .customSelect(
              'SELECT COUNT(*) AS n, COALESCE(SUM(s.discount), 0) AS d '
              'FROM sales s WHERE s.voucher_code = ?4 AND s.return_of_id '
              'IS NULL AND s.sale_date >= ?1 AND s.sale_date < ?2 AND $store',
              variables: [
                ...vars(a.createdAt, now.add(const Duration(days: 1))),
                Variable.withString(code),
              ],
            )
            .getSingle();
        Future<int?> basket(DateTime from, DateTime to) async {
          final r = await _db
              .customSelect(
                'SELECT AVG(s.total) AS v FROM sales s WHERE s.return_of_id '
                'IS NULL AND s.sale_date >= ?1 AND s.sale_date < ?2 AND $store',
                variables: vars(from, to),
              )
              .getSingle();
          return (r.data['v'] as num?)?.round();
        }

        out.add(
          PromoResult(
            kind: kind,
            title: a.title,
            at: a.createdAt,
            daysAfter: daysAfter,
            voucherCode: code,
            uses: used.read<int>('n'),
            discount: (used.data['d'] as num).toInt(),
            basketBefore: await basket(start, a.createdAt),
            basketAfter: await basket(
              a.createdAt,
              now.add(const Duration(days: 1)),
            ),
          ),
        );
      } else if (a.productId case final productId?) {
        Future<(double, int)> sold(DateTime from, DateTime to) async {
          final r = await _db
              .customSelect(
                'SELECT COALESCE(SUM(si.qty * si.unit_factor), 0) AS q, '
                'COALESCE(SUM(si.subtotal), 0) AS r FROM sale_items si '
                'JOIN sales s ON s.id = si.sale_id WHERE si.product_id = ?4 '
                'AND s.sale_date >= ?1 AND s.sale_date < ?2 AND $store',
                variables: [...vars(from, to), Variable.withInt(productId)],
              )
              .getSingle();
          return (
            (r.data['q'] as num).toDouble(),
            (r.data['r'] as num).toInt(),
          );
        }

        final before = await sold(start, a.createdAt);
        final after = await sold(a.createdAt, now.add(const Duration(days: 1)));
        out.add(
          PromoResult(
            kind: kind,
            title: a.title,
            at: a.createdAt,
            daysAfter: daysAfter,
            qtyBefore: before.$1,
            revenueBefore: before.$2,
            qtyAfter: after.$1,
            revenueAfter: after.$2,
          ),
        );
      }
    }
    return out;
  }
}

final promoResultsProvider = FutureProvider.autoDispose<List<PromoResult>>(
  (ref) => ref.watch(promoRepositoryProvider).results(),
);

final promoRepositoryProvider = Provider<PromoRepository>(
  (ref) => PromoRepository(
    ref.watch(appDatabaseProvider),
    storeId: ref.watch(storeScopeProvider),
  ),
);

final promoSuggestionsProvider =
    FutureProvider.autoDispose<List<PromoSuggestion>>(
      (ref) => ref.watch(promoRepositoryProvider).suggestions(),
    );
