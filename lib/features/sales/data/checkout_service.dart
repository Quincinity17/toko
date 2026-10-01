import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../auth/domain/app_user.dart';
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
  });

  final int saleId;
  final String invoiceNo;
  final int total;
  final int paid;
  final int change;
}

/// Menyimpan transaksi penjualan: faktur, baris barang, pengurangan stok, dan
/// riwayat stok, semuanya dalam satu database transaction. Jika satu langkah
/// gagal, tidak ada yang tersimpan.
class CheckoutService {
  CheckoutService(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  Future<CheckoutResult> checkout({
    required Cart cart,
    required AppUser cashier,
    required int paid,
  }) async {
    if (cart.isEmpty) {
      throw const CheckoutFailure('Keranjang masih kosong.');
    }
    if (cart.lines.any((l) => l.qty <= 0)) {
      throw const CheckoutFailure('Jumlah barang harus lebih dari 0.');
    }
    if (paid < cart.total) {
      throw const CheckoutFailure('Uang yang dibayar kurang dari total.');
    }

    final now = _clock();
    return _db.transaction(() async {
      final invoiceNo = InvoiceNumber.next(
        now,
        await _db.salesDao.lastInvoiceWithPrefix(InvoiceNumber.prefixFor(now)),
      );

      final saleId = await _db
          .into(_db.sales)
          .insert(
            SalesCompanion.insert(
              invoiceNo: invoiceNo,
              saleDate: now,
              userId: cashier.id,
              itemCount: cart.lines.length,
              subtotal: cart.subtotal,
              discountPercent: Value(
                cart.discountType == DiscountType.percent &&
                        cart.discountValue > 0
                    ? cart.discountValue
                    : null,
              ),
              discount: Value(cart.discount),
              total: cart.total,
              paid: paid,
              changeAmount: paid - cart.total,
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
                discountPercent: Value(line.discountPercent),
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

      return CheckoutResult(
        saleId: saleId,
        invoiceNo: invoiceNo,
        total: cart.total,
        paid: paid,
        change: paid - cart.total,
      );
    });
  }
}

final checkoutServiceProvider = Provider<CheckoutService>(
  (ref) => CheckoutService(ref.watch(appDatabaseProvider)),
);
