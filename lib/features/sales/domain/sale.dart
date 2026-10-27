import 'package:flutter/foundation.dart';

import 'split_payment.dart';

/// Ringkasan faktur untuk daftar transaksi.
@immutable
class SaleSummary {
  const SaleSummary({
    required this.id,
    required this.invoiceNo,
    required this.date,
    required this.cashierName,
    required this.itemCount,
    required this.subtotal,
    required this.discount,
    this.discountPercent,
    this.voucherCode,
    required this.total,
    required this.paid,
    required this.change,
    required this.paymentMethod,
    this.paymentRef,
    this.storeId,
    this.returnOfId,
    this.returnReason,
    this.returnedAmount = 0,
    this.exchangeOfId,
    this.payments = const [],
  });

  final int id;
  final String invoiceNo;
  final DateTime date;
  final String cashierName;
  final int itemCount;
  final int subtotal;
  final int discount;

  /// Hanya faktur lama yang punya potongan persen manual.
  final double? discountPercent;

  /// Kode voucher yang dipakai (sumber [discount]).
  final String? voucherCode;
  final int total;
  final int paid;
  final int change;
  final String paymentMethod;
  final String? paymentRef;
  final int? storeId;

  /// Nota retur (`RET-…`, total negatif): faktur asal yang diretur.
  final int? returnOfId;
  final String? returnReason;

  /// Faktur penjualan: nilai yang sudah diretur (positif).
  final int returnedAmount;

  /// Faktur tukar barang: nota retur yang menjadi kreditnya.
  final int? exchangeOfId;

  /// Split payment: nilai per metode (kosong = hanya [paymentMethod]).
  final List<SalePart> payments;

  bool get isSplit => payments.isNotEmpty;

  /// Nilai per metode bayar (faktur biasa: total ke [paymentMethod]).
  List<(String, int)> get amountsByMethod => isSplit
      ? [for (final p in payments) (p.name, p.amount)]
      : [(paymentMethod, total)];

  bool get isExchange => exchangeOfId != null;

  bool get isReturn => returnOfId != null;

  /// Seluruh nilai faktur sudah dikembalikan (dibatalkan).
  bool get isFullyReturned => !isReturn && total > 0 && returnedAmount >= total;
  bool get isPartlyReturned =>
      !isReturn && returnedAmount > 0 && !isFullyReturned;
}

/// Baris faktur yang sudah tersimpan.
@immutable
class SaleLine {
  const SaleLine({
    required this.code,
    required this.name,
    this.unitName,
    required this.qty,
    required this.price,
    required this.discountPercent,
    required this.subtotal,
    this.unitFactor = 1,
  });

  final String code;
  final String name;
  final String? unitName;
  final double qty;
  final int price;
  final double discountPercent;
  final int subtotal;

  /// Isi satuan baris ini dalam satuan dasar (multi-satuan).
  final double unitFactor;
}
