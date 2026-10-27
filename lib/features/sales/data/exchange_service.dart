import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../auth/domain/app_user.dart';
import '../domain/cart.dart';
import '../domain/split_payment.dart';
import 'checkout_service.dart';
import 'return_service.dart';

/// Hasil tukar barang: nota retur (barang dikembalikan) + faktur baru
/// (barang pengganti) yang dibayar sebagian dengan kredit nota retur.
class ExchangeResult {
  const ExchangeResult({required this.returned, required this.sale});

  final ReturnResult returned;
  final CheckoutResult sale;
}

/// Tukar barang (permintaan user): satu database transaction berisi
/// 1. nota retur `RET-…` untuk barang yang dikembalikan (aturan & hak sama
///    dengan retur biasa), dicatat dengan metode penyelesaian, lalu
/// 2. faktur `INV-…` untuk barang pengganti (`sales.exchange_of_id` = nota
///    retur) dengan kredit = nilai retur; pelanggan membayar selisihnya atau
///    menerima kembalian.
///
/// Kedua faktur memakai metode penyelesaian yang sama, jadi total per metode
/// (tutup kasir) = uang yang benar-benar berpindah (selisih saja). Stok
/// barang kembali dan barang pengganti berkurang, keduanya di toko faktur
/// asal. Gagal di langkah mana pun = tidak ada yang tersimpan.
class ExchangeService {
  ExchangeService(this._db, {DateTime Function()? clock})
    : _returns = ReturnService(_db, clock: clock),
      _checkout = CheckoutService(_db, clock: clock);

  final AppDatabase _db;
  final ReturnService _returns;
  final CheckoutService _checkout;

  Future<ExchangeResult> exchange({
    required AppUser actor,
    required int saleId,
    required Map<int, double> qtys,
    required String reason,
    required Cart replacement,
    int? paymentMethodId,
    int? paid,
    String? paymentRef,
    List<PaymentPart>? split,
  }) async {
    // Bayar terpisah: nota retur memakai metode bagian pertama (tunai dulu,
    // sama dengan urutan SplitPayment.settle).
    final settle =
        paymentMethodId ??
        (split ?? const <PaymentPart>[])
            .firstWhere((p) => p.isCash, orElse: () => split!.first)
            .methodId;
    if (replacement.isEmpty) {
      throw const CheckoutFailure(
        'Tambahkan barang pengganti (tanpa pengganti = retur biasa).',
      );
    }
    final storeId = (await _returns.load(saleId)).storeId;
    if (storeId == null) {
      throw const ReturnFailure('Faktur ini tidak punya toko.');
    }
    return _db.transaction(() async {
      final returned = await _returns.create(
        actor: actor,
        saleId: saleId,
        qtys: qtys,
        reason: reason,
        settleMethodId: settle,
        exchange: true,
      );
      final sale = await _checkout.checkout(
        cart: replacement,
        cashier: actor,
        storeId: storeId,
        paymentMethodId: split == null ? paymentMethodId : null,
        split: split,
        paid: paid,
        paymentRef: paymentRef,
        credit: returned.refund,
        exchangeOfId: returned.saleId,
      );
      return ExchangeResult(returned: returned, sale: sale);
    });
  }
}

final exchangeServiceProvider = Provider<ExchangeService>(
  (ref) => ExchangeService(ref.watch(appDatabaseProvider)),
);
