import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/sale.dart';

class SalesRepository {
  SalesRepository(this._db);

  final AppDatabase _db;

  /// Transaksi pada tanggal [day] (jam diabaikan), terbaru dulu.
  /// [storeId] `null` = semua toko.
  Stream<List<SaleSummary>> watchDay(DateTime day, {int? storeId}) {
    final start = DateTime(day.year, day.month, day.day);
    return watchBetween(
      start,
      DateTime(day.year, day.month, day.day + 1),
      storeId: storeId,
    );
  }

  /// Transaksi dalam rentang [start, end), terbaru dulu.
  Stream<List<SaleSummary>> watchBetween(
    DateTime start,
    DateTime end, {
    int? storeId,
  }) {
    return _db.salesDao
        .watchSalesBetween(start, end, storeId: storeId)
        .map(
          (rows) => [
            for (final (s, cashier) in rows)
              SaleSummary(
                id: s.id,
                invoiceNo: s.invoiceNo,
                date: s.saleDate,
                cashierName: cashier,
                itemCount: s.itemCount,
                subtotal: s.subtotal,
                discount: s.discount,
                discountPercent: s.discountPercent,
                total: s.total,
                paid: s.paid,
                change: s.changeAmount,
                paymentMethod: s.paymentMethod,
                paymentRef: s.paymentRef,
              ),
          ],
        );
  }

  Future<List<SaleLine>> linesOf(int saleId) async {
    final rows = await _db.salesDao.itemsOf(saleId);
    return [
      for (final r in rows)
        SaleLine(
          code: r.productCode,
          name: r.productName,
          unitName: r.unitName,
          qty: r.qty,
          price: r.price,
          discountPercent: r.discountPercent,
          subtotal: r.subtotal,
        ),
    ];
  }
}

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(ref.watch(appDatabaseProvider)),
);
