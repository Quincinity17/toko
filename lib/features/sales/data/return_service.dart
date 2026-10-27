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
import '../../auth/domain/permission.dart';
import '../../payments/domain/payment_method.dart';
import '../../sync/data/terminal_repository.dart';
import '../../sync/domain/terminal.dart';
import '../domain/invoice_number.dart';
import '../domain/sale_return.dart';
import '../domain/split_payment.dart';

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
    this.payments = const [],
  });

  final int saleId;
  final String invoiceNo;

  /// Uang yang dikembalikan ke pelanggan (positif).
  final int refund;
  final String paymentMethod;
  final bool isCash;

  /// Faktur split payment: uang kembali per metode (nilai negatif).
  final List<SalePart> payments;

  /// Keterangan cara mengembalikan, mis. "Tunai" atau
  /// "Tunai Rp 20.000 + QRIS Rp 5.000".
  String get refundMethods => payments.isEmpty
      ? paymentMethod
      : payments.map((p) => '${p.name} ${Fmt.rupiah(-p.amount)}').join(' + ');
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
      user.isAdmin ||
      (storeId != null &&
          user.storeId == storeId &&
          user.can(Permission.returnSale));

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
    final parts = await _db.salesDao.paymentsOf(saleId);
    final refunded = parts.isEmpty
        ? const <int?, int>{}
        : await _db.salesDao.refundedByMethod(saleId);
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
            unitFactor: i.unitFactor,
          ),
      ],
      payments: [
        for (final p in parts)
          SalePart(
            methodId: p.paymentMethodId,
            name: p.methodName,
            amount: p.amount - (refunded[p.paymentMethodId] ?? 0),
            isCash: p.isCash,
          ),
      ],
    );
  }

  /// Memeriksa pilihan retur tanpa menyimpan (dipakai sebelum tukar
  /// barang). Mengembalikan nilai kredit/uang kembali.
  Future<int> check({
    required AppUser actor,
    required int saleId,
    required Map<int, double> qtys,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) throw const ReturnFailure('Alasan wajib diisi.');
    final sale = await load(saleId);
    _pick(actor, sale, qtys);
    return sale.refundFor(qtys);
  }

  /// Baris yang dipilih untuk diretur; melempar [ReturnFailure] bila tidak
  /// sah.
  List<(ReturnableLine, double)> _pick(
    AppUser actor,
    ReturnableSale sale,
    Map<int, double> qtys,
  ) {
    if (!canReturn(actor, sale.storeId)) {
      throw const ReturnFailure(
        'Anda tidak punya hak retur untuk faktur toko ini.',
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
        'Faktur dengan voucher/potongan hanya bisa dibatalkan seluruhnya.',
      );
    }
    return picked;
  }

  /// [qtys]: `id baris faktur → jumlah dikembalikan`. Faktur berpotongan
  /// (lama) hanya bisa dibatalkan seluruhnya.
  ///
  /// Tukar barang ([exchange], lewat `ExchangeService`): nilai retur menjadi
  /// kredit faktur penukaran, dan nota retur dicatat dengan metode
  /// penyelesaian [settleMethodId] (supaya total per metode = uang yang
  /// benar-benar berpindah).
  Future<ReturnResult> create({
    required AppUser actor,
    required int saleId,
    required Map<int, double> qtys,
    required String reason,
    int? settleMethodId,
    bool exchange = false,
  }) async {
    final why = reason.trim();
    if (why.isEmpty) throw const ReturnFailure('Alasan wajib diisi.');

    return _db.transaction(() async {
      final sale = await load(saleId);
      final picked = _pick(actor, sale, qtys);
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

      // Metode nota: metode faktur asal, atau metode penyelesaian tukar.
      var methodName = original.paymentMethod;
      var methodId = original.paymentMethodId;
      var isCash = sale.isCash;
      // Faktur split payment: uang kembali dibagi ke metode asalnya (tunai
      // dulu). Tukar barang memakai metode penyelesaiannya sendiri.
      final refundParts = settleMethodId == null && sale.isSplit
          ? SplitPayment.allocateRefund(sale.payments, refund)
          : const <SalePart>[];
      if (refundParts.isNotEmpty) {
        methodName = SplitPayment.joinedName(refundParts.map((p) => p.name));
        methodId = refundParts.first.methodId;
        isCash = refundParts.any((p) => p.isCash);
      }
      if (settleMethodId != null) {
        final m = await _db.paymentMethodsDao.findById(settleMethodId);
        if (m == null || !m.isActive) {
          throw const ReturnFailure('Metode pembayaran tidak tersedia.');
        }
        methodName = m.name;
        methodId = m.id;
        isCash = m.kind == PaymentKind.cash;
      }
      final note = exchange ? 'Tukar barang: $why' : why;

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
              // Faktur bervoucher (hanya batal semua): subtotal, potongan,
              // dan voucher dicerminkan supaya laporan kembali nol.
              subtotal: sale.hasDiscount ? -original.subtotal : -refund,
              discount: Value(sale.hasDiscount ? -original.discount : 0),
              voucherId: Value(sale.hasDiscount ? original.voucherId : null),
              voucherCode: Value(
                sale.hasDiscount ? original.voucherCode : null,
              ),
              total: -refund,
              paid: -refund,
              changeAmount: 0,
              paymentMethod: Value(methodName),
              paymentMethodId: Value(methodId),
              returnOfId: Value(saleId),
              returnReason: Value(note),
            ),
          );
      for (final p in refundParts) {
        await _db
            .into(_db.salePayments)
            .insert(
              SalePaymentsCompanion.insert(
                saleId: returnId,
                paymentMethodId: Value(p.methodId),
                methodName: p.name,
                isCash: Value(p.isCash),
                amount: p.amount,
                tendered: p.amount,
              ),
            );
      }

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
                unitFactor: Value(l.unitFactor),
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
            delta: q * l.unitFactor,
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
            '${exchange ? 'kredit tukar' : 'kembali'} ${Fmt.rupiah(refund)}. '
            'Alasan: $note',
        userId: actor.id,
        userName: actor.fullName,
        storeId: original.storeId,
        data: {
          'uuid': uuid,
          'invoice': invoiceNo,
          'original': sale.invoiceNo,
          'total': -refund,
          'refund': refund,
          'reason': note,
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
        paymentMethod: methodName,
        isCash: isCash,
        payments: refundParts,
      );
    });
  }

  static String _qty(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}

final returnServiceProvider = Provider<ReturnService>(
  (ref) => ReturnService(ref.watch(appDatabaseProvider)),
);
