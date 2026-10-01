import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/sale.dart';

class SalesRepository {
  SalesRepository(this._db);

  final AppDatabase _db;

  /// Transaksi pada tanggal [day] (jam diabaikan), terbaru dulu.
  Stream<List<SaleSummary>> watchDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _db.salesDao
        .watchSalesBetween(start, end)
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
                voucherCode: s.voucherCode,
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
