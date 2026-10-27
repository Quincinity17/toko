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
import '../../vouchers/data/voucher_repository.dart';
import '../domain/cart.dart';
import '../domain/invoice_number.dart';
import '../domain/split_payment.dart';

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
    required this.isCash,
    this.voucherCode,
    this.discount = 0,
    this.credit = 0,
    this.payments = const [],
  });

  final int saleId;
  final String invoiceNo;
  final int total;
  final int paid;
  final int change;
  final String paymentMethod;

  /// Metode tunai: laci uang dibuka (jika diatur).
  final bool isCash;
  final String? voucherCode;
  final int discount;

  /// Tukar barang: kredit dari nota retur yang ikut membayar faktur ini.
  /// [paid] = kredit + uang dari pelanggan; [change] = uang ke pelanggan.
  final int credit;

  /// Split payment: nilai per metode (kosong = satu metode).
  final List<SalePart> payments;
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
  /// Stok yang dikurangi adalah stok toko [storeId].
  ///
  /// Tukar barang (`ExchangeService`): [credit] = nilai nota retur
  /// [exchangeOfId]; pelanggan hanya membayar sisanya ([paid] = uang tunai
  /// yang diterima), atau menerima kelebihannya sebagai kembalian.
  ///
  /// Split payment: [split] (≥ 2 metode, lihat [SplitPayment.settle])
  /// menggantikan [paymentMethodId]/[paid]/[paymentRef].
  Future<CheckoutResult> checkout({
    required Cart cart,
    required AppUser cashier,
    required int storeId,
    int? paymentMethodId,
    List<PaymentPart>? split,
    int? paid,
    String? paymentRef,
    int credit = 0,
    int? exchangeOfId,
  }) async {
    if (credit < 0 || (credit > 0 && exchangeOfId == null)) {
      throw const CheckoutFailure('Kredit tukar barang tidak sah.');
    }
    if (exchangeOfId != null && cart.voucher != null) {
      throw const CheckoutFailure('Voucher tidak bisa dipakai saat tukar.');
    }
    if (cart.isEmpty) {
      throw const CheckoutFailure('Keranjang masih kosong.');
    }
    if (cart.lines.any((l) => l.qty <= 0)) {
      throw const CheckoutFailure('Jumlah barang harus lebih dari 0.');
    }
    if (!cashier.canSellAt(storeId)) {
      throw const CheckoutFailure('Anda tidak terdaftar di toko ini.');
    }
    if (split == null && paymentMethodId == null) {
      throw const CheckoutFailure('Pilih metode pembayaran.');
    }

    final now = _clock();
    return _db.transaction(() async {
      final store = await _db.storesDao.findById(storeId);
      if (store == null || !store.isActive) {
        throw const CheckoutFailure('Toko tidak ditemukan atau nonaktif.');
      }
      // Nama & jenis metode diambil dari database, bukan dari isian.
      Future<PaymentMethodRow> method(int id) async {
        final row = await _db.paymentMethodsDao.findById(id);
        if (row == null || !row.isActive) {
          throw const CheckoutFailure('Metode pembayaran tidak tersedia.');
        }
        return row;
      }

      final methodRow = split == null ? await method(paymentMethodId!) : null;
      final parts = [
        for (final p in split ?? const <PaymentPart>[])
          if (await method(p.methodId) case final row)
            PaymentPart(
              methodId: row.id,
              name: row.name,
              isCash: row.kind == PaymentKind.cash,
              amount: p.amount,
              ref: p.ref?.trim().isEmpty ?? true ? null : p.ref!.trim(),
            ),
      ];

      // Voucher diperiksa ulang dari database: bisa saja sudah dinonaktifkan,
      // kedaluwarsa, atau diubah sejak dipasang di keranjang.
      final subtotal = cart.subtotal;
      var discount = 0;
      String? voucherCode;
      int? voucherId;
      if (cart.voucher case final applied?) {
        if (!cashier.can(Permission.useVoucher)) {
          throw const CheckoutFailure('Anda tidak punya hak memakai voucher.');
        }
        final row = await _db.vouchersDao.findById(applied.id);
        if (row == null) {
          throw const CheckoutFailure('Voucher sudah dihapus. Lepas voucher.');
        }
        final voucher = voucherFromRow(row);
        final problem = voucher.problemFor(
          subtotal: subtotal,
          now: now,
          storeId: storeId,
        );
        if (problem != null) throw CheckoutFailure(problem);
        discount = voucher.discountFor(subtotal);
        if (discount != cart.discount) {
          throw const CheckoutFailure(
            'Voucher baru saja diubah admin. Lepas lalu pasang lagi.',
          );
        }
        voucherCode = voucher.code;
        voucherId = voucher.id;
      }

      final total = subtotal - discount;
      final due = total > credit ? total - credit : 0;
      final List<SettledPart> settled;
      final int paidValue;
      final bool isCash;
      final String methodName;
      final int methodId;
      String? ref;
      if (methodRow != null) {
        isCash = methodRow.kind == PaymentKind.cash;
        final money = isCash ? (paid ?? 0) : due;
        if (money < due) {
          throw const CheckoutFailure('Uang yang dibayar kurang dari total.');
        }
        settled = const [];
        paidValue = credit + money;
        methodName = methodRow.name;
        methodId = methodRow.id;
        ref = paymentRef?.trim();
      } else {
        if (due <= 0) {
          throw const CheckoutFailure(
            'Tidak ada yang perlu dibayar; tidak perlu bayar terpisah.',
          );
        }
        try {
          final result = SplitPayment.settle(parts, due);
          settled = result.parts;
          paidValue = credit + due + result.change;
        } on SplitPaymentFailure catch (e) {
          throw CheckoutFailure(e.message);
        }
        isCash = settled.any((p) => p.part.isCash);
        methodName = SplitPayment.joinedName(settled.map((p) => p.part.name));
        methodId = settled.first.part.methodId;
      }

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
              storeId: Value(storeId),
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
              paymentMethod: Value(methodName),
              paymentMethodId: Value(methodId),
              paymentRef: Value(ref == null || ref.isEmpty ? null : ref),
              exchangeOfId: Value(exchangeOfId),
            ),
          );
      for (final (i, p) in settled.indexed) {
        await _db
            .into(_db.salePayments)
            .insert(
              SalePaymentsCompanion.insert(
                saleId: saleId,
                paymentMethodId: Value(p.part.methodId),
                methodName: p.part.name,
                isCash: Value(p.part.isCash),
                // Tukar barang: kredit nota retur dicatat di bagian pertama
                // (nota returnya memakai metode yang sama), jadi total per
                // metode = uang yang benar-benar berpindah.
                amount: p.applied + (i == 0 ? credit : 0),
                tendered: p.part.amount,
                ref: Value(p.part.ref),
              ),
            );
      }

      for (final line in cart.lines) {
        await _db
            .into(_db.saleItems)
            .insert(
              SaleItemsCompanion.insert(
                saleId: saleId,
                productId: line.product.id,
                productCode: line.product.code,
                productName: line.product.name,
                unitName: Value(line.unitName),
                qty: line.qty,
                price: line.price,
                purchasePrice: line.purchasePrice,
                subtotal: line.total,
                unitFactor: Value(line.factor),
              ),
            );
        await _db.storesDao.changeStock(
          storeId: storeId,
          productId: line.product.id,
          delta: -line.baseQty,
          type: StockMovementType.sale,
          userId: cashier.id,
          refId: saleId,
          note: invoiceNo,
        );
      }

      // Masuk antrian kirim ke server di transaksi yang sama: jika faktur
      // tersimpan, antriannya pasti ada.
      await _db.outboxDao.enqueue(OutboxEntity.sale, saleUuid);

      // Catatan aktivitas + sidik jari isi faktur (pemeriksaan keutuhan).
      await _db.auditDao.append(
        type: AuditType.sale,
        summary:
            '$invoiceNo · ${cart.lines.length} barang · ${Fmt.rupiah(total)} '
            '($methodName)'
            '${voucherCode == null ? '' : ' · voucher $voucherCode −${Fmt.rupiah(discount)}'}',
        userId: cashier.id,
        userName: cashier.fullName,
        storeId: storeId,
        data: {
          'uuid': saleUuid,
          'invoice': invoiceNo,
          'total': total,
          if (settled.isNotEmpty)
            'payments': {for (final p in settled) p.part.name: p.applied},
          'voucher': ?voucherCode,
          if (voucherCode != null) 'discount': discount,
          'digest': saleDigest(
            uuid: saleUuid,
            invoiceNo: invoiceNo,
            total: total,
            items: [
              for (final l in cart.lines)
                (
                  productId: l.product.id,
                  qty: l.qty,
                  price: l.price,
                  subtotal: l.total,
                ),
            ],
          ),
        },
        at: now,
      );

      return CheckoutResult(
        saleId: saleId,
        invoiceNo: invoiceNo,
        total: total,
        paid: paidValue,
        change: paidValue - total,
        paymentMethod: methodName,
        isCash: isCash,
        voucherCode: voucherCode,
        discount: discount,
        credit: credit,
        payments: [
          for (final p in settled)
            SalePart(
              methodId: p.part.methodId,
              name: p.part.name,
              amount: p.applied,
              isCash: p.part.isCash,
              tendered: p.part.amount,
              ref: p.part.ref,
            ),
        ],
      );
    });
  }
}

final checkoutServiceProvider = Provider<CheckoutService>(
  (ref) => CheckoutService(ref.watch(appDatabaseProvider)),
);
