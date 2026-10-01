import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/sync.dart';
import '../../../core/database/uuid.dart';
import '../../auth/domain/app_user.dart';
import '../../payments/domain/payment_method.dart';
import '../../sync/data/terminal_repository.dart';
import '../../sync/domain/terminal.dart';
import '../../vouchers/data/voucher_repository.dart';
import '../domain/cart.dart';
import '../domain/invoice_number.dart';

class CheckoutFailure implements Exception {
  const CheckoutFailure(this.message);

  final String message;

  @override
  String toString() => 'CheckoutFailure: $message';
}

/// Hasil transaksi yang berhasil disimpan.
class CheckoutResult {
  const CheckoutResult({
    required this.saleId,
    required this.invoiceNo,
    required this.total,
    required this.paid,
    required this.change,
    required this.paymentMethod,
    this.voucherCode,
    this.discount = 0,
  });

  final int saleId;
  final String invoiceNo;
  final int total;
  final int paid;
  final int change;
  final String paymentMethod;
  final String? voucherCode;
  final int discount;
}

/// Menyimpan transaksi penjualan: faktur, baris barang, pengurangan stok,
/// riwayat stok, dan antrian kirim ke server (outbox), semuanya dalam satu
/// database transaction. Jika satu langkah gagal, tidak ada yang tersimpan.
class CheckoutService {
  CheckoutService(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// [paid] diabaikan untuk metode non-tunai (dianggap pas sesuai total).
  Future<CheckoutResult> checkout({
    required Cart cart,
    required AppUser cashier,
    required int paymentMethodId,
    int? paid,
    String? paymentRef,
  }) async {
    if (cart.isEmpty) {
      throw const CheckoutFailure('Keranjang masih kosong.');
    }
    if (cart.lines.any((l) => l.qty <= 0)) {
      throw const CheckoutFailure('Jumlah barang harus lebih dari 0.');
    }

    final now = _clock();
    return _db.transaction(() async {
      final methodRow = await _db.paymentMethodsDao.findById(paymentMethodId);
      if (methodRow == null || !methodRow.isActive) {
        throw const CheckoutFailure('Metode pembayaran tidak tersedia.');
      }

      // Voucher diperiksa ulang dari database: bisa saja sudah dinonaktifkan
      // atau kedaluwarsa sejak dipasang di keranjang.
      final subtotal = cart.subtotal;
      var discount = 0;
      String? voucherCode;
      int? voucherId;
      if (cart.voucher case final applied?) {
        final row = await _db.vouchersDao.findById(applied.id);
        if (row == null) {
          throw const CheckoutFailure('Voucher sudah dihapus. Lepas voucher.');
        }
        final voucher = voucherFromRow(row);
        final problem = voucher.problemFor(subtotal: subtotal, now: now);
        if (problem != null) throw CheckoutFailure(problem);
        discount = voucher.discountFor(subtotal);
        voucherCode = voucher.code;
        voucherId = voucher.id;
      }

      final total = subtotal - discount;
      final isCash = methodRow.kind == PaymentKind.cash;
      final paidValue = isCash ? (paid ?? 0) : total;
      if (paidValue < total) {
        throw const CheckoutFailure('Uang yang dibayar kurang dari total.');
      }
      final ref = paymentRef?.trim();

      final terminalCode =
          await _db.settingsDao.get(TerminalRepository.kCode) ??
          Terminal.defaultCode;
      final invoiceNo = InvoiceNumber.next(
        now,
        terminalCode,
        await _db.salesDao.lastInvoiceWithPrefix(
          InvoiceNumber.prefixFor(now, terminalCode),
        ),
      );
      final saleUuid = newUuid();

      final saleId = await _db
          .into(_db.sales)
          .insert(
            SalesCompanion.insert(
              uuid: Value(saleUuid),
              invoiceNo: invoiceNo,
              terminalCode: Value(terminalCode),
              saleDate: now,
              userId: cashier.id,
              itemCount: cart.lines.length,
              subtotal: subtotal,
              discount: Value(discount),
              voucherId: Value(voucherId),
              voucherCode: Value(voucherCode),
              total: total,
              paid: paidValue,
              changeAmount: paidValue - total,
              paymentMethod: Value(methodRow.name),
              paymentMethodId: Value(methodRow.id),
              paymentRef: Value(ref == null || ref.isEmpty ? null : ref),
            ),
          );

      for (final line in cart.lines) {
        await _db
            .into(_db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                saleId: saleId,
                productId: line.product.id,
                productCode: line.product.code,
                productName: line.product.name,
                unitName: Value(line.product.unitName),
                qty: line.qty,
                price: line.price,
                purchasePrice: line.product.purchasePrice,
                subtotal: line.total,
              ),
            );
        await _db.salesDao.decreaseStock(
          productId: line.product.id,
          qty: line.qty,
          saleId: saleId,
          invoiceNo: invoiceNo,
        );
      }

      // Masuk antrian kirim ke server di transaksi yang sama: jika faktur
      // tersimpan, antriannya pasti ada.
      await _db.outboxDao.enqueue(OutboxEntity.sale, saleUuid);

      return CheckoutResult(
        saleId: saleId,
        invoiceNo: invoiceNo,
        total: total,
        paid: paidValue,
        change: paidValue - total,
        paymentMethod: methodRow.name,
        voucherCode: voucherCode,
        discount: discount,
      );
    });
  }
}

final checkoutServiceProvider = Provider<CheckoutService>(
  (ref) => CheckoutService(ref.watch(appDatabaseProvider)),
);
