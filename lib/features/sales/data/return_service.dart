import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/audit.dart';
import '../../../core/database/tables/sales.dart';
import '../../../core/database/tables/sync.dart';
import '../../../core/database/uuid.dart';
import '../../../core/utils/formatters.dart';
import '../../audit/domain/sale_digest.dart';
import '../../auth/domain/app_user.dart';
import '../../payments/domain/payment_method.dart';
import '../../sync/data/terminal_repository.dart';
import '../../sync/domain/terminal.dart';
import '../domain/invoice_number.dart';
import '../domain/sale_return.dart';

class ReturnFailure implements Exception {
  const ReturnFailure(this.message);

  final String message;

  @override
  String toString() => 'ReturnFailure: $message';
}

/// Nota retur yang tersimpan.
class ReturnResult {
  const ReturnResult({
    required this.saleId,
    required this.invoiceNo,
    required this.refund,
    required this.paymentMethod,
    required this.isCash,
  });

  final int saleId;
  final String invoiceNo;

  /// Uang yang dikembalikan ke pelanggan (positif).
  final int refund;
  final String paymentMethod;
  final bool isCash;
}

/// Retur sebagian atau batal seluruh faktur.
///
/// Disimpan sebagai **nota retur** (`RET-<terminal>-YYYYMMDD-0001`): baris
/// `sales` bernilai negatif dengan `return_of_id` = faktur asal, barisnya
/// qty & subtotal negatif (`return_of_item_id` = baris asal), harga beli
/// disalin dari baris asal. Faktur asal tidak diubah. Akibatnya semua
/// laporan (omzet, laba, per barang/metode/kasir) terpotong otomatis pada
/// tanggal retur; jumlah transaksi tidak menghitung nota retur. Stok kembali
/// (riwayat jenis `saleReturn`), dan nota masuk antrian sinkron.
///
/// Hanya admin & supervisor toko faktur itu (sama dengan hak ubah stok).
class ReturnService {
  ReturnService(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Boleh meretur faktur toko [storeId].
  static bool canReturn(AppUser user, int? storeId) =>
      user.isAdmin || (storeId != null && user.canAdjustStockAt(storeId));

  Future<ReturnableSale> load(int saleId) async {
    final sale = await (_db.select(
      _db.sales,
    )..where((s) => s.id.equals(saleId))).getSingleOrNull();
    if (sale == null) throw const ReturnFailure('Faktur tidak ditemukan.');
    if (sale.returnOfId != null) {
      throw const ReturnFailure('Nota retur tidak bisa diretur lagi.');
    }
    final method = sale.paymentMethodId == null
        ? null
        : await _db.paymentMethodsDao.findById(sale.paymentMethodId!);
    final returned = await _db.salesDao.returnedByItem(saleId);
    final items = await _db.salesDao.itemsOf(saleId);
    return ReturnableSale(
      saleId: sale.id,
      invoiceNo: sale.invoiceNo,
      storeId: sale.storeId,
      total: sale.total,
      discount: sale.discount,
      paymentMethod: sale.paymentMethod,
      // Faktur lama tanpa id metode: dibayar tunai.
      isCash: method == null || method.kind == PaymentKind.cash,
      lines: [
        for (final i in items)
          ReturnableLine(
            saleItemId: i.id,
            productId: i.productId,
            code: i.productCode,
            name: i.productName,
            unitName: i.unitName,
            soldQty: i.qty,
            price: i.price,
            purchasePrice: i.purchasePrice,
            subtotal: i.subtotal,
            returnedQty: returned[i.id]?.$1 ?? 0,
            returnedSubtotal: returned[i.id]?.$2 ?? 0,
          ),
      ],
    );
  }

  /// [qtys]: `id baris faktur → jumlah dikembalikan`. Faktur berpotongan
  /// (lama) hanya bisa dibatalkan seluruhnya.
  Future<ReturnResult> create({
    required AppUser actor,
    required int saleId,
    required Map<int, double> qtys,
    required String reason,
  }) async {
    final why = reason.trim();
    if (why.isEmpty) throw const ReturnFailure('Alasan wajib diisi.');

    return _db.transaction(() async {
      final sale = await load(saleId);
      if (!canReturn(actor, sale.storeId)) {
        throw const ReturnFailure(
          'Hanya admin atau supervisor toko ini yang bisa meretur faktur.',
        );
      }
      if (sale.fullyReturned) {
        throw const ReturnFailure('Semua barang di faktur ini sudah diretur.');
      }

      final picked = <(ReturnableLine, double)>[];
      for (final l in sale.lines) {
        final q = qtys[l.saleItemId] ?? 0;
        if (q < 0) throw const ReturnFailure('Jumlah tidak boleh negatif.');
        if (q == 0) continue;
        if (q > l.returnable + 1e-9) {
          throw ReturnFailure(
            '${l.name}: paling banyak ${_qty(l.returnable)} yang bisa '
            'diretur.',
          );
        }
        picked.add((l, q));
      }
      if (picked.isEmpty) {
        throw const ReturnFailure('Pilih minimal satu barang yang diretur.');
      }
      final returnsAll =
          picked.length == sale.lines.length &&
          picked.every((p) => (p.$2 - p.$1.returnable).abs() < 1e-9);
      if (sale.hasDiscount && !returnsAll) {
        throw const ReturnFailure(
          'Faktur dengan potongan hanya bisa dibatalkan seluruhnya.',
        );
      }

      final refund = sale.refundFor(qtys);
      final now = _clock();
      final terminalCode =
          await _db.settingsDao.get(TerminalRepository.kCode) ??
          Terminal.defaultCode;
      final type = InvoiceNumber.saleReturn;
      final invoiceNo = InvoiceNumber.next(
        now,
        terminalCode,
        await _db.salesDao.lastInvoiceWithPrefix(
          InvoiceNumber.prefixFor(now, terminalCode, type: type),
        ),
        type: type,
      );
      final original = await (_db.select(
        _db.sales,
      )..where((s) => s.id.equals(saleId))).getSingle();
      final uuid = newUuid();

      final returnId = await _db
          .into(_db.sales)
          .insert(
            SalesCompanion.insert(
              uuid: Value(uuid),
              invoiceNo: invoiceNo,
              terminalCode: Value(terminalCode),
              storeId: Value(original.storeId),
              saleDate: now,
              userId: actor.id,
              itemCount: picked.length,
              subtotal: -refund,
              total: -refund,
              paid: -refund,
              changeAmount: 0,
              paymentMethod: Value(original.paymentMethod),
              paymentMethodId: Value(original.paymentMethodId),
              returnOfId: Value(saleId),
              returnReason: Value(why),
            ),
          );

      for (final (l, q) in picked) {
        await _db
            .into(_db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                saleId: returnId,
                productId: l.productId,
                productCode: l.code,
                productName: l.name,
                unitName: Value(l.unitName),
                qty: -q,
                price: l.price,
                purchasePrice: l.purchasePrice,
                // Faktur berpotongan (batal semua): nilai per baris tetap
                // subtotal asal; selisih potongan ada di total nota.
                subtotal: -l.refundFor(q),
                returnOfItemId: Value(l.saleItemId),
              ),
            );
        if (original.storeId case final storeId?) {
          await _db.storesDao.changeStock(
            storeId: storeId,
            productId: l.productId,
            delta: q,
            type: StockMovementType.saleReturn,
            userId: actor.id,
            refId: returnId,
            note: '$invoiceNo (${sale.invoiceNo})',
          );
        }
      }

      await _db.outboxDao.enqueue(OutboxEntity.sale, uuid);

      await _db.auditDao.append(
        type: AuditType.saleReturn,
        summary:
            '$invoiceNo dari ${sale.invoiceNo}: ${picked.length} barang, '
            'kembali ${Fmt.rupiah(refund)}. Alasan: $why',
        userId: actor.id,
        userName: actor.fullName,
        storeId: original.storeId,
        data: {
          'uuid': uuid,
          'invoice': invoiceNo,
          'original': sale.invoiceNo,
          'total': -refund,
          'refund': refund,
          'reason': why,
          'digest': saleDigest(
            uuid: uuid,
            invoiceNo: invoiceNo,
            total: -refund,
            items: [
              for (final (l, q) in picked)
                (
                  productId: l.productId,
                  qty: -q,
                  price: l.price,
                  subtotal: -l.refundFor(q),
                ),
            ],
          ),
        },
        at: now,
      );

      return ReturnResult(
        saleId: returnId,
        invoiceNo: invoiceNo,
        refund: refund,
        paymentMethod: original.paymentMethod,
        isCash: sale.isCash,
      );
    });
  }

  static String _qty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

final returnServiceProvider = Provider<ReturnService>(
  (ref) => ReturnService(ref.watch(appDatabaseProvider)),
);
