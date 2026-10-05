import 'package:flutter/foundation.dart';

/// Satu baris faktur yang bisa diretur.
@immutable
class ReturnableLine {
  const ReturnableLine({
    required this.saleItemId,
    required this.productId,
    required this.code,
    required this.name,
    this.unitName,
    required this.soldQty,
    required this.price,
    required this.purchasePrice,
    required this.subtotal,
    this.returnedQty = 0,
    this.returnedSubtotal = 0,
  });

  final int saleItemId;
  final int productId;
  final String code;
  final String name;
  final String? unitName;
  final double soldQty;
  final int price;
  final int purchasePrice;

  /// Subtotal baris di faktur asal.
  final int subtotal;

  /// Sudah diretur sebelumnya (positif).
  final double returnedQty;
  final int returnedSubtotal;

  /// Sisa yang masih bisa diretur.
  double get returnable => soldQty - returnedQty;

  /// Uang yang dikembalikan untuk [qty]. Mengembalikan seluruh sisa = sisa
  /// subtotal persis (tanpa selisih pembulatan); sebagian = round(qty ×
  /// harga), sama dengan cara faktur menghitung.
  int refundFor(double qty) {
    if (qty <= 0) return 0;
    if ((qty - returnable).abs() < 1e-9) return subtotal - returnedSubtotal;
    return (qty * price).round();
  }
}

/// Faktur beserta barisnya, untuk popup retur/batal.
@immutable
class ReturnableSale {
  const ReturnableSale({
    required this.saleId,
    required this.invoiceNo,
    required this.storeId,
    required this.total,
    required this.discount,
    required this.paymentMethod,
    required this.isCash,
    required this.lines,
  });

  final int saleId;
  final String invoiceNo;
  final int? storeId;
  final int total;

  /// Hanya faktur lama (voucher) yang punya potongan; faktur seperti ini
  /// hanya bisa dibatalkan seluruhnya supaya uang kembali = yang dibayar.
  final int discount;
  final String paymentMethod;
  final bool isCash;
  final List<ReturnableLine> lines;

  bool get hasDiscount => discount > 0;
  bool get fullyReturned => lines.every((l) => l.returnable <= 1e-9);

  /// Total uang kembali untuk [qtys] (`saleItemId → qty`).
  int refundFor(Map<int, double> qtys) {
    if (hasDiscount) {
      // Hanya batal semua: uang kembali = total yang dibayar.
      return total;
    }
    var sum = 0;
    for (final l in lines) {
      sum += l.refundFor(qtys[l.saleItemId] ?? 0);
    }
    return sum;
  }
}
