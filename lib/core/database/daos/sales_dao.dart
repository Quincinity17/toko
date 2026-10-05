import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/products.dart';
import '../tables/sales.dart';
import '../tables/users.dart';

part 'sales_dao.g.dart';

@DriftAccessor(tables: [Sales, SaleItems, StockMovements, Products, Users])
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

  /// Faktur dalam rentang [start, end), terbaru dulu, beserta nama kasir dan
  /// nilai yang sudah diretur. [storeId] `null` = semua toko.
  Stream<List<(SaleRow, String, int)>> watchSalesBetween(
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
          ..addColumns([_returned]);
    return query
        .map(
          (r) => (
            r.readTable(sales),
            r.readTable(users).fullName,
            r.read(_returned) ?? 0,
          ),
        )
        .watch();
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
