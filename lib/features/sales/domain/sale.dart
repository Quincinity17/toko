import 'package:flutter/foundation.dart';

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
  });

  final int id;
  final String invoiceNo;
  final DateTime date;
  final String cashierName;
  final int itemCount;
  final int subtotal;
  final int discount;

  /// Hanya faktur lama (sebelum voucher) yang punya potongan persen manual.
  final double? discountPercent;
  final String? voucherCode;
  final int total;
  final int paid;
  final int change;
  final String paymentMethod;
  final String? paymentRef;
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
  });

  final String code;
  final String name;
  final String? unitName;
  final double qty;
  final int price;
  final double discountPercent;
  final int subtotal;
}
