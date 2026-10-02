import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/products.dart';
import '../tables/sales.dart';
import '../tables/stores.dart';
import '../tables/tags.dart';
import '../tables/users.dart';

part 'reports_dao.g.dart';

/// Query agregat untuk dashboard dan laporan. Semua rentang [start, end)
/// dan pengelompokan tanggal/jam memakai waktu lokal komputer.
///
/// Mengembalikan [Selectable] supaya bisa dibaca sekali (`get`) untuk halaman
/// laporan, atau dipantau (`watch`) untuk dashboard yang selalu terbaru.
///
/// [storeId] `null` = semua toko. Di SQL: `?3` (penjualan) atau `?2` (stok).
@DriftAccessor(
  tables: [
    Sales,
    SaleItems,
    Products,
    Users,
    Stores,
    StoreProducts,
    Tags,
    ProductTags,
  ],
)
class ReportsDao extends DatabaseAccessor<AppDatabase> with _$ReportsDaoMixin {
  ReportsDao(super.attachedDatabase);

  static const _local = "'unixepoch', 'localtime'";

  List<Variable<Object>> _range(DateTime start, DateTime end, int? storeId) => [
    Variable.withDateTime(start),
    Variable.withDateTime(end),
    Variable<int>(storeId),
  ];

  /// Filter toko untuk tabel sales dengan alias [alias].
  static String _store(String alias) => '(?3 IS NULL OR $alias.store_id = ?3)';

  /// Satu baris: tx, revenue, gross, discount, cost, qty.
  Selectable<QueryRow> summary(DateTime start, DateTime end, {int? storeId}) =>
      customSelect(
        '''
    SELECT
      (SELECT COUNT(*) FROM sales s WHERE s.sale_date >= ?1 AND s.sale_date < ?2
         AND ${_store('s')}) AS tx,
      (SELECT COALESCE(SUM(total), 0) FROM sales s
         WHERE s.sale_date >= ?1 AND s.sale_date < ?2
         AND ${_store('s')}) AS revenue,
      (SELECT COALESCE(SUM(subtotal), 0) FROM sales s
         WHERE s.sale_date >= ?1 AND s.sale_date < ?2
         AND ${_store('s')}) AS gross,
      (SELECT COALESCE(SUM(discount), 0) FROM sales s
         WHERE s.sale_date >= ?1 AND s.sale_date < ?2
         AND ${_store('s')}) AS discount,
      (SELECT COALESCE(SUM(si.qty * si.purchase_price), 0)
         FROM sale_items si JOIN sales s ON s.id = si.sale_id
         WHERE s.sale_date >= ?1 AND s.sale_date < ?2
         AND ${_store('s')}) AS cost,
      (SELECT COALESCE(SUM(si.qty), 0)
         FROM sale_items si JOIN sales s ON s.id = si.sale_id
         WHERE s.sale_date >= ?1 AND s.sale_date < ?2
         AND ${_store('s')}) AS qty
    ''',
        variables: _range(start, end, storeId),
        readsFrom: {sales, saleItems},
      );

  /// Per tanggal lokal (`yyyy-mm-dd`): tx, revenue, cost. Hari tanpa
  /// penjualan tidak muncul (diisi nol oleh repository).
  Selectable<QueryRow> daily(DateTime start, DateTime end, {int? storeId}) =>
      customSelect(
        '''
    SELECT d.day, d.tx, d.revenue, COALESCE(c.cost, 0) AS cost
    FROM (
      SELECT date(sale_date, $_local) AS day, COUNT(*) AS tx,
             SUM(total) AS revenue
      FROM sales s WHERE s.sale_date >= ?1 AND s.sale_date < ?2
        AND ${_store('s')}
      GROUP BY day
    ) d
    LEFT JOIN (
      SELECT date(s.sale_date, $_local) AS day,
             SUM(si.qty * si.purchase_price) AS cost
      FROM sale_items si JOIN sales s ON s.id = si.sale_id
      WHERE s.sale_date >= ?1 AND s.sale_date < ?2 AND ${_store('s')}
      GROUP BY day
    ) c ON c.day = d.day
    ORDER BY d.day
    ''',
        variables: _range(start, end, storeId),
        readsFrom: {sales, saleItems},
      );

  /// Per jam (`%H`, 0–23) atau per hari dalam seminggu (`%w`, 0 = Minggu).
  Selectable<QueryRow> buckets(
    DateTime start,
    DateTime end,
    String format, {
    int? storeId,
  }) => customSelect(
    '''
        SELECT CAST(strftime('$format', sale_date, $_local) AS INTEGER) AS bucket,
               COUNT(*) AS tx, SUM(total) AS revenue
        FROM sales s WHERE s.sale_date >= ?1 AND s.sale_date < ?2
          AND ${_store('s')}
        GROUP BY bucket ORDER BY bucket
        ''',
    variables: _range(start, end, storeId),
    readsFrom: {sales},
  );

  /// Per barang: kode/nama dari faktur, kategori (tag, dipisah koma) &
  /// satuan terkini.
  Selectable<QueryRow> productSales(
    DateTime start,
    DateTime end, {
    int? storeId,
    int? limit,
  }) => customSelect(
    '''
    SELECT si.product_id, MAX(si.product_code) AS code,
           MAX(si.product_name) AS name, MAX(si.unit_name) AS unit,
           (SELECT group_concat(t.name, ', ') FROM product_tags pt
            JOIN tags t ON t.id = pt.tag_id
            WHERE pt.product_id = si.product_id) AS category,
           SUM(si.qty) AS qty, SUM(si.subtotal) AS revenue,
           SUM(si.qty * si.purchase_price) AS cost,
           COUNT(DISTINCT si.sale_id) AS tx
    FROM sale_items si
    JOIN sales s ON s.id = si.sale_id
    WHERE s.sale_date >= ?1 AND s.sale_date < ?2 AND ${_store('s')}
    GROUP BY si.product_id
    ORDER BY qty DESC, revenue DESC
    ${limit == null ? '' : 'LIMIT $limit'}
    ''',
    variables: _range(start, end, storeId),
    readsFrom: {sales, saleItems, productTags, tags},
  );

  /// Per kategori (tag, kategori saat ini). Barang dengan beberapa kategori
  /// dihitung di setiap kategorinya; barang tanpa kategori = "Tanpa kategori".
  Selectable<QueryRow> categorySales(
    DateTime start,
    DateTime end, {
    int? storeId,
  }) => customSelect(
    '''
        SELECT COALESCE(t.name, 'Tanpa kategori') AS grp,
               COUNT(DISTINCT si.sale_id) AS tx, SUM(si.qty) AS qty,
               SUM(si.subtotal) AS revenue,
               SUM(si.qty * si.purchase_price) AS cost
        FROM sale_items si
        JOIN sales s ON s.id = si.sale_id
        LEFT JOIN product_tags pt ON pt.product_id = si.product_id
        LEFT JOIN tags t ON t.id = pt.tag_id
        WHERE s.sale_date >= ?1 AND s.sale_date < ?2 AND ${_store('s')}
        GROUP BY grp ORDER BY revenue DESC
        ''',
    variables: _range(start, end, storeId),
    readsFrom: {sales, saleItems, productTags, tags},
  );

  /// Dikelompokkan per [groupExpr] milik tabel sales (alias `s`), mis.
  /// metode bayar, kasir, terminal. Biaya per faktur dihitung dari
  /// item supaya laba per kelompok bisa diketahui.
  Selectable<QueryRow> _bySale(
    DateTime start,
    DateTime end,
    String groupExpr, {
    int? storeId,
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
    WHERE s.sale_date >= ?1 AND s.sale_date < ?2 AND ${_store('s')} $where
    GROUP BY grp ORDER BY revenue DESC
    ''',
    variables: _range(start, end, storeId),
    readsFrom: {sales, saleItems, users, stores},
  );

  Selectable<QueryRow> paymentSales(
    DateTime start,
    DateTime end, {
    int? storeId,
  }) => _bySale(start, end, 's.payment_method', storeId: storeId);

  Selectable<QueryRow> cashierSales(
    DateTime start,
    DateTime end, {
    int? storeId,
  }) => _bySale(
    start,
    end,
    'u.full_name',
    storeId: storeId,
    join: 'JOIN users u ON u.id = s.user_id',
  );

  Selectable<QueryRow> terminalSales(
    DateTime start,
    DateTime end, {
    int? storeId,
  }) => _bySale(
    start,
    end,
    "COALESCE(s.terminal_code, '(sebelum kode terminal)')",
    storeId: storeId,
  );

  Selectable<QueryRow> storeSales(
    DateTime start,
    DateTime end, {
    int? storeId,
  }) => _bySale(
    start,
    end,
    "COALESCE(st.name, '(tanpa toko)')",
    storeId: storeId,
    join: 'LEFT JOIN stores st ON st.id = s.store_id',
  );

  /// Nilai persediaan barang aktif yang stoknya > 0 di toko [storeId]
  /// (`null` = semua toko). Nilai jual memakai harga toko masing-masing.
  Selectable<QueryRow> inventory({int? storeId}) => customSelect(
    '''
    SELECT COUNT(DISTINCT p.id) AS products,
           COALESCE(SUM(sp.stock * p.purchase_price), 0) AS cost_value,
           COALESCE(SUM(sp.stock * COALESCE(sp.selling_price, p.selling_price)),
                    0) AS retail_value
    FROM store_products sp JOIN products p ON p.id = sp.product_id
    WHERE p.is_active = 1 AND sp.stock > 0
      AND (?1 IS NULL OR sp.store_id = ?1)
    ''',
    variables: [Variable<int>(storeId)],
    readsFrom: {products, storeProducts},
  );

  /// Setiap barang aktif: stok (toko [storeId] atau jumlah semua toko), harga
  /// beli, total terjual sejak [since], dan tanggal terakhir terjual.
  Selectable<QueryRow> stockStatus(DateTime since, {int? storeId}) =>
      customSelect(
        '''
        SELECT p.id, p.code, p.name, u.name AS unit, p.purchase_price,
               COALESCE((SELECT SUM(sp.stock) FROM store_products sp
                 WHERE sp.product_id = p.id
                   AND (?2 IS NULL OR sp.store_id = ?2)), 0) AS stock,
               COALESCE(r.qty, 0) AS recent_qty, l.last_sold
        FROM products p
        LEFT JOIN units u ON u.id = p.unit_id
        LEFT JOIN (
          SELECT si.product_id, SUM(si.qty) AS qty
          FROM sale_items si JOIN sales s ON s.id = si.sale_id
          WHERE s.sale_date >= ?1 AND (?2 IS NULL OR s.store_id = ?2)
          GROUP BY si.product_id
        ) r ON r.product_id = p.id
        LEFT JOIN (
          SELECT si.product_id, MAX(s.sale_date) AS last_sold
          FROM sale_items si JOIN sales s ON s.id = si.sale_id
          WHERE (?2 IS NULL OR s.store_id = ?2)
          GROUP BY si.product_id
        ) l ON l.product_id = p.id
        WHERE p.is_active = 1
        ''',
        variables: [Variable.withDateTime(since), Variable<int>(storeId)],
        readsFrom: {sales, saleItems, products, storeProducts},
      );
}
