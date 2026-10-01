import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/products.dart';
import '../tables/sales.dart';
import '../tables/users.dart';

part 'reports_dao.g.dart';

/// Query agregat untuk dashboard dan laporan. Semua rentang [start, end)
/// dan pengelompokan tanggal/jam memakai waktu lokal komputer.
///
/// Mengembalikan [Selectable] supaya bisa dibaca sekali (`get`) untuk halaman
/// laporan, atau dipantau (`watch`) untuk dashboard yang selalu terbaru.
@DriftAccessor(tables: [Sales, SaleItems, Products, Categories, Users])
class ReportsDao extends DatabaseAccessor<AppDatabase> with _$ReportsDaoMixin {
  ReportsDao(super.attachedDatabase);

  static const _local = "'unixepoch', 'localtime'";

  List<Variable<Object>> _range(DateTime start, DateTime end) => [
    Variable.withDateTime(start),
    Variable.withDateTime(end),
  ];

  /// Satu baris: tx, revenue, gross, discount, cost, qty.
  Selectable<QueryRow> summary(DateTime start, DateTime end) => customSelect(
    '''
    SELECT
      (SELECT COUNT(*) FROM sales WHERE sale_date >= ?1 AND sale_date < ?2) AS tx,
      (SELECT COALESCE(SUM(total), 0) FROM sales
         WHERE sale_date >= ?1 AND sale_date < ?2) AS revenue,
      (SELECT COALESCE(SUM(subtotal), 0) FROM sales
         WHERE sale_date >= ?1 AND sale_date < ?2) AS gross,
      (SELECT COALESCE(SUM(discount), 0) FROM sales
         WHERE sale_date >= ?1 AND sale_date < ?2) AS discount,
      (SELECT COALESCE(SUM(si.qty * si.purchase_price), 0)
         FROM sale_items si JOIN sales s ON s.id = si.sale_id
         WHERE s.sale_date >= ?1 AND s.sale_date < ?2) AS cost,
      (SELECT COALESCE(SUM(si.qty), 0)
         FROM sale_items si JOIN sales s ON s.id = si.sale_id
         WHERE s.sale_date >= ?1 AND s.sale_date < ?2) AS qty
    ''',
    variables: _range(start, end),
    readsFrom: {sales, saleItems},
  );

  /// Per tanggal lokal (`yyyy-mm-dd`): tx, revenue, cost. Hari tanpa
  /// penjualan tidak muncul (diisi nol oleh repository).
  Selectable<QueryRow> daily(DateTime start, DateTime end) => customSelect(
    '''
    SELECT d.day, d.tx, d.revenue, COALESCE(c.cost, 0) AS cost
    FROM (
      SELECT date(sale_date, $_local) AS day, COUNT(*) AS tx,
             SUM(total) AS revenue
      FROM sales WHERE sale_date >= ?1 AND sale_date < ?2
      GROUP BY day
    ) d
    LEFT JOIN (
      SELECT date(s.sale_date, $_local) AS day,
             SUM(si.qty * si.purchase_price) AS cost
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      WHERE s.sale_date >= ?1 AND s.sale_date < ?2
      GROUP BY day
    ) c ON c.day = d.day
    ORDER BY d.day
    ''',
    variables: _range(start, end),
    readsFrom: {sales, saleItems},
  );

  /// Per jam (`%H`, 0–23) atau per hari dalam seminggu (`%w`, 0 = Minggu).
  Selectable<QueryRow> buckets(DateTime start, DateTime end, String format) =>
      customSelect(
        '''
        SELECT CAST(strftime('$format', sale_date, $_local) AS INTEGER) AS bucket,
               COUNT(*) AS tx, SUM(total) AS revenue
        FROM sales WHERE sale_date >= ?1 AND sale_date < ?2
        GROUP BY bucket ORDER BY bucket
        ''',
        variables: _range(start, end),
        readsFrom: {sales},
      );

  /// Per barang: kode/nama dari faktur, kategori & satuan terkini.
  Selectable<QueryRow> productSales(
    DateTime start,
    DateTime end, {
    int? limit,
  }) => customSelect(
    '''
    SELECT si.product_id, MAX(si.product_code) AS code,
           MAX(si.product_name) AS name, MAX(si.unit_name) AS unit,
           c.name AS category,
           SUM(si.qty) AS qty, SUM(si.subtotal) AS revenue,
           SUM(si.qty * si.purchase_price) AS cost,
           COUNT(DISTINCT si.sale_id) AS tx
    FROM sale_items si
    JOIN sales s ON s.id = si.sale_id
    LEFT JOIN products p ON p.id = si.product_id
    LEFT JOIN categories c ON c.id = p.category_id
    WHERE s.sale_date >= ?1 AND s.sale_date < ?2
    GROUP BY si.product_id
    ORDER BY qty DESC, revenue DESC
    ${limit == null ? '' : 'LIMIT $limit'}
    ''',
    variables: _range(start, end),
    readsFrom: {sales, saleItems, products, categories},
  );

  Selectable<QueryRow> categorySales(DateTime start, DateTime end) =>
      customSelect(
        '''
        SELECT COALESCE(c.name, 'Tanpa kategori') AS grp,
               COUNT(DISTINCT si.sale_id) AS tx, SUM(si.qty) AS qty,
               SUM(si.subtotal) AS revenue,
               SUM(si.qty * si.purchase_price) AS cost
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        LEFT JOIN products p ON p.id = si.product_id
        LEFT JOIN categories c ON c.id = p.category_id
        WHERE s.sale_date >= ?1 AND s.sale_date < ?2
        GROUP BY grp ORDER BY revenue DESC
        ''',
        variables: _range(start, end),
        readsFrom: {sales, saleItems, products, categories},
      );

  /// Dikelompokkan per [groupExpr] milik tabel sales (alias `s`), mis.
  /// metode bayar, kasir, terminal. Biaya per faktur dihitung dari
  /// item supaya laba per kelompok bisa diketahui.
  Selectable<QueryRow> _bySale(
    DateTime start,
    DateTime end,
    String groupExpr, {
    String join = '',
    String where = '',
  }) => customSelect(
    '''
    SELECT $groupExpr AS grp, COUNT(*) AS tx, SUM(s.total) AS revenue,
           SUM(s.discount) AS discount, SUM(COALESCE(ic.cost, 0)) AS cost
    FROM sales s
    LEFT JOIN (
      SELECT sale_id, SUM(qty * purchase_price) AS cost
      FROM sale_items GROUP BY sale_id
    ) ic ON ic.sale_id = s.id
    $join
    WHERE s.sale_date >= ?1 AND s.sale_date < ?2 $where
    GROUP BY grp ORDER BY revenue DESC
    ''',
    variables: _range(start, end),
    readsFrom: {sales, saleItems, users},
  );

  Selectable<QueryRow> paymentSales(DateTime start, DateTime end) =>
      _bySale(start, end, 's.payment_method');

  Selectable<QueryRow> cashierSales(DateTime start, DateTime end) => _bySale(
    start,
    end,
    'u.full_name',
    join: 'JOIN users u ON u.id = s.user_id',
  );

  Selectable<QueryRow> terminalSales(DateTime start, DateTime end) => _bySale(
    start,
    end,
    "COALESCE(s.terminal_code, '(sebelum kode terminal)')",
  );

  /// Nilai persediaan barang aktif yang stoknya > 0.
  Selectable<QueryRow> inventory() => customSelect(
    '''
    SELECT COUNT(*) AS products,
           COALESCE(SUM(stock * purchase_price), 0) AS cost_value,
           COALESCE(SUM(stock * selling_price), 0) AS retail_value
    FROM products WHERE is_active = 1 AND stock > 0
    ''',
    readsFrom: {products},
  );

  /// Setiap barang aktif: stok, harga beli, total terjual sejak [since], dan
  /// tanggal terakhir terjual (kapan pun).
  Selectable<QueryRow> stockStatus(DateTime since) => customSelect(
    '''
    SELECT p.id, p.code, p.name, u.name AS unit, p.stock, p.purchase_price,
           COALESCE(r.qty, 0) AS recent_qty, l.last_sold
    FROM products p
    LEFT JOIN units u ON u.id = p.unit_id
    LEFT JOIN (
      SELECT si.product_id, SUM(si.qty) AS qty
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      WHERE s.sale_date >= ?1 GROUP BY si.product_id
    ) r ON r.product_id = p.id
    LEFT JOIN (
      SELECT si.product_id, MAX(s.sale_date) AS last_sold
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      GROUP BY si.product_id
    ) l ON l.product_id = p.id
    WHERE p.is_active = 1
    ''',
    variables: [Variable.withDateTime(since)],
    readsFrom: {sales, saleItems, products},
  );
}
