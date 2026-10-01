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

  /// Faktur dalam rentang [start, end), terbaru dulu, beserta nama kasir.
  Stream<List<(SaleRow, String)>> watchSalesBetween(
    DateTime start,
    DateTime end,
  ) {
    final query =
        select(sales).join([innerJoin(users, users.id.equalsExp(sales.userId))])
          ..where(
            sales.saleDate.isBiggerOrEqualValue(start) &
                sales.saleDate.isSmallerThanValue(end),
          )
          ..orderBy([OrderingTerm.desc(sales.saleDate)]);
    return query
        .map((r) => (r.readTable(sales), r.readTable(users).fullName))
        .watch();
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

  /// Mengurangi stok dan mencatat riwayatnya. Dipanggil di dalam transaksi.
  Future<void> decreaseStock({
    required int productId,
    required double qty,
    required int saleId,
    required String invoiceNo,
  }) async {
    await customUpdate(
      'UPDATE products SET stock = stock - ?, updated_at = ? WHERE id = ?',
      variables: [
        Variable.withReal(qty),
        Variable.withDateTime(DateTime.now()),
        Variable.withInt(productId),
      ],
      updates: {products},
    );
    await into(stockMovements).insert(
      StockMovementsCompanion.insert(
        productId: productId,
        type: StockMovementType.sale,
        qtyChange: -qty,
        refId: Value(saleId),
        note: Value(invoiceNo),
      ),
    );
  }
}
