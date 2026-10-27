import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../domain/sale.dart';
import '../domain/split_payment.dart';

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
            for (final (s, cashier, returned, payments) in rows)
              _summary(s, cashier, returned, payments),
          ],
        );
  }

  /// Faktur (semua tanggal) yang nomornya memuat [query], terbaru dulu.
  Future<List<SaleSummary>> search(String query, {int? storeId}) async {
    final q = query.trim();
    if (q.isEmpty || q.replaceAll(RegExp(r'[%_\\]'), '').isEmpty) {
      return const [];
    }
    return [
      for (final (s, cashier, returned, payments)
          in await _db.salesDao.searchSales(q, storeId: storeId))
        _summary(s, cashier, returned, payments),
    ];
  }

  static List<SalePart> _parts(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return [
      for (final item in raw.split('\u001f'))
        if (item.split('\u001e') case [
          final name,
          final amount,
          final cash,
          final ref,
          final tendered,
        ])
          SalePart(
            name: name,
            amount: int.parse(amount),
            isCash: cash == '1',
            ref: ref.isEmpty ? null : ref,
            tendered: int.tryParse(tendered),
          ),
    ];
  }

  static SaleSummary _summary(
    SaleRow s,
    String cashier,
    int returned,
    String? payments,
  ) => SaleSummary(
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
    storeId: s.storeId,
    returnOfId: s.returnOfId,
    returnReason: s.returnReason,
    returnedAmount: returned,
    exchangeOfId: s.exchangeOfId,
    payments: _parts(payments),
  );

  /// Faktur tukar barang: nota retur kreditnya ([returnId]) dan faktur
  /// asalnya.
  Future<({String returnNo, String? originalNo, int credit})?> exchangeInfo(
    int returnId,
  ) async {
    final ret = await (_db.select(
      _db.sales,
    )..where((s) => s.id.equals(returnId))).getSingleOrNull();
    if (ret == null) return null;
    final original = ret.returnOfId == null
        ? null
        : await (_db.select(
            _db.sales,
          )..where((s) => s.id.equals(ret.returnOfId!))).getSingleOrNull();
    return (
      returnNo: ret.invoiceNo,
      originalNo: original?.invoiceNo,
      credit: -ret.total,
    );
  }

  /// Pembayaran terpisah faktur [saleId] (kosong = satu metode).
  Future<List<SalePart>> paymentsOf(int saleId) async => [
    for (final p in await _db.salesDao.paymentsOf(saleId))
      SalePart(
        methodId: p.paymentMethodId,
        name: p.methodName,
        amount: p.amount,
        isCash: p.isCash,
        tendered: p.tendered,
        ref: p.ref,
      ),
  ];

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
          unitFactor: r.unitFactor,
        ),
    ];
  }
}

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SalesRepository(ref.watch(appDatabaseProvider)),
);
