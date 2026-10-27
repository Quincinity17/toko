import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/products.dart';
import '../tables/sales.dart';
import '../tables/users.dart';

part 'sales_dao.g.dart';

@DriftAccessor(
  tables: [Sales, SaleItems, StockMovements, Products, Users, SalePayments],
)
class SalesDao extends DatabaseAccessor<AppDatabase> with _$SalesDaoMixin {
  SalesDao(super.attachedDatabase);

  /// Nomor faktur terakhir yang diawali [prefix], misalnya `INV-20260930-`.
  Future<String?> lastInvoiceWithPrefix(String prefix) async {
    final query = selectOnly(sales)
      ..addColumns([sales.invoiceNo])
      ..where(sales.invoiceNo.like('$prefix%'))
      ..orderBy([OrderingTerm.desc(sales.invoiceNo)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.read(sales.invoiceNo);
  }

  /// Nilai yang sudah diretur dari faktur (positif), dari nota retur.
  static final _returned = CustomExpression<int>(
    '(SELECT COALESCE(-SUM(r.total), 0) FROM sales r '
    'WHERE r.return_of_id = sales.id)',
  );

  /// Pembayaran terpisah: `nama␞nilai␞tunai(0/1)␞ref␞diterima` dipisah `␟`,
  /// urut id.
  late final _paymentList = CustomExpression<String>(
    "(SELECT group_concat(x, char(31)) FROM (SELECT p.method_name || "
    "char(30) || p.amount || char(30) || p.is_cash || char(30) || "
    "COALESCE(p.ref, '') || char(30) || p.tendered AS x FROM sale_payments p "
    'WHERE p.sale_id = sales.id ORDER BY p.id))',
    watchedTables: [salePayments],
  );

  /// Faktur dalam rentang [start, end), terbaru dulu, beserta nama kasir,
  /// nilai yang sudah diretur, dan pembayaran terpisahnya (lihat
  /// [_paymentList]). [storeId] `null` = semua toko.
  Stream<List<(SaleRow, String, int, String?)>> watchSalesBetween(
    DateTime start,
    DateTime end, {
    int? storeId,
  }) {
    final query =
        select(sales).join([innerJoin(users, users.id.equalsExp(sales.userId))])
          ..where(
            sales.saleDate.isBiggerOrEqualValue(start) &
                sales.saleDate.isSmallerThanValue(end) &
                (storeId == null
                    ? const Constant(true)
                    : sales.storeId.equals(storeId)),
          )
          ..orderBy([OrderingTerm.desc(sales.saleDate)])
          ..addColumns([_returned, _paymentList]);
    return query
        .map(
          (r) => (
            r.readTable(sales),
            r.readTable(users).fullName,
            r.read(_returned) ?? 0,
            r.read(_paymentList),
          ),
        )
        .watch();
  }

  /// Faktur (semua tanggal) yang nomornya memuat [query], terbaru dulu.
  /// Dipakai kasir untuk mencari faktur lama dari nomor di struk.
  Future<List<(SaleRow, String, int, String?)>> searchSales(
    String query, {
    int? storeId,
    int limit = 50,
  }) {
    final q = query.trim().toUpperCase().replaceAll(RegExp(r'[%_\\]'), '');
    final found =
        select(sales).join([innerJoin(users, users.id.equalsExp(sales.userId))])
          ..where(
            sales.invoiceNo.upper().like('%$q%') &
                (storeId == null
                    ? const Constant(true)
                    : sales.storeId.equals(storeId)),
          )
          ..orderBy([OrderingTerm.desc(sales.saleDate)])
          ..limit(limit)
          ..addColumns([_returned, _paymentList]);
    return found
        .map(
          (r) => (
            r.readTable(sales),
            r.readTable(users).fullName,
            r.read(_returned) ?? 0,
            r.read(_paymentList),
          ),
        )
        .get();
  }

  /// Satu faktur beserta nama kasirnya.
  Future<(SaleRow, String)?> findWithCashier(int saleId) {
    final query = select(sales).join([
      innerJoin(users, users.id.equalsExp(sales.userId)),
    ])..where(sales.id.equals(saleId));
    return query
        .map((r) => (r.readTable(sales), r.readTable(users).fullName))
        .getSingleOrNull();
  }

  /// Jumlah & nilai (positif) yang sudah diretur per baris faktur [saleId]:
  /// `id baris asal → (qty, subtotal)`.
  Future<Map<int, (double, int)>> returnedByItem(int saleId) async {
    final rows = await customSelect(
      'SELECT si.return_of_item_id AS item, -SUM(si.qty) AS qty, '
      '-SUM(si.subtotal) AS subtotal '
      'FROM sale_items si JOIN sales s ON s.id = si.sale_id '
      'WHERE s.return_of_id = ? AND si.return_of_item_id IS NOT NULL '
      'GROUP BY si.return_of_item_id',
      variables: [Variable.withInt(saleId)],
      readsFrom: {sales, saleItems},
    ).get();
    return {
      for (final r in rows)
        r.read<int>('item'): (
          (r.data['qty'] as num).toDouble(),
          (r.data['subtotal'] as num).toInt(),
        ),
    };
  }

  /// Pembayaran terpisah faktur [saleId] (kosong = satu metode), urut
  /// disimpan.
  Future<List<SalePaymentRow>> paymentsOf(int saleId) =>
      (select(salePayments)
            ..where((p) => p.saleId.equals(saleId))
            ..orderBy([(p) => OrderingTerm.asc(p.id)]))
          .get();

  /// Uang yang sudah dikembalikan nota retur faktur split [saleId] per
  /// metode (positif): `id metode → nilai`.
  Future<Map<int?, int>> refundedByMethod(int saleId) async {
    final rows = await customSelect(
      'SELECT p.payment_method_id AS method, -SUM(p.amount) AS amount '
      'FROM sale_payments p JOIN sales s ON s.id = p.sale_id '
      'WHERE s.return_of_id = ? GROUP BY p.payment_method_id',
      variables: [Variable.withInt(saleId)],
      readsFrom: {sales, salePayments},
    ).get();
    return {
      for (final r in rows)
        r.read<int?>('method'): (r.data['amount'] as num).toInt(),
    };
  }

  Future<List<SaleItemRow>> itemsOf(int saleId) {
    return (select(saleItems)
          ..where((i) => i.saleId.equals(saleId))
          ..orderBy([(i) => OrderingTerm.asc(i.id)]))
        .get();
  }

  Future<int> countByUser(int userId) async {
    final count = sales.id.count();
    final row =
        await (selectOnly(sales)
              ..addColumns([count])
              ..where(sales.userId.equals(userId)))
            .getSingle();
    return row.read(count) ?? 0;
  }
}
