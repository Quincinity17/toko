import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Sidik jari isi faktur/nota retur (SHA-256). Disimpan di catatan aktivitas
/// saat faktur dibuat; pemeriksaan keutuhan menghitung ulang dari database
/// → faktur yang diubah/dihapus di luar aplikasi ketahuan.
String saleDigest({
  required String uuid,
  required String invoiceNo,
  required int total,
  required Iterable<({int productId, double qty, int price, int subtotal})>
  items,
}) {
  String n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  final lines = [
    for (final i in items)
      '${i.productId}:${n(i.qty)}:${i.price}:${i.subtotal}',
  ]..sort();
  return sha256
      .convert(utf8.encode('$uuid|$invoiceNo|$total|${lines.join(';')}'))
      .toString();
}
