import 'package:flutter/cupertino.dart';

import '../domain/payment_method.dart';

/// Ikon yang cocok untuk metode pembayaran, ditebak dari jenis dan namanya.
IconData paymentMethodIcon(PaymentMethod m) {
  if (m.isCash) return CupertinoIcons.money_dollar_circle_fill;
  final n = m.name.toLowerCase();
  if (n.contains('qris') || n.contains('qr')) return CupertinoIcons.qrcode;
  if (n.contains('transfer') || n.contains('bank')) {
    return CupertinoIcons.building_2_fill;
  }
  if (n.contains('kartu') ||
      n.contains('debit') ||
      n.contains('kredit') ||
      n.contains('card') ||
      n.contains('edc')) {
    return CupertinoIcons.creditcard_fill;
  }
  if (['ovo', 'gopay', 'dana', 'shopee', 'wallet', 'linkaja'].any(n.contains)) {
    return CupertinoIcons.device_phone_portrait;
  }
  return CupertinoIcons.creditcard;
}
