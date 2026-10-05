import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'device_keys.dart';

/// Segel data: HMAC-SHA256 dengan kunci rahasia perangkat
/// ([DeviceKeys.sealKey]) atas kolom-kolom penting sebuah baris. Baris yang
/// diubah di luar aplikasi (mis. role akun dinaikkan jadi admin, harga atau
/// stok diubah lewat DB Browser) segelnya tidak cocok lagi → tertangkap
/// pemeriksaan keutuhan (`IntegrityService`).
class Sealer {
  Sealer(List<int> key) : _hmac = Hmac(sha256, key);

  factory Sealer.forTests() => Sealer(DeviceKeys.forTests().sealKey);

  final Hmac _hmac;

  /// Bentuk baku setiap nilai supaya segel sama walau dibaca ulang dari
  /// database (mis. REAL 12.0 = 12, DateTime = detik unix).
  static String _canon(Object? v) => switch (v) {
    null => '∅',
    final double d when d == d.roundToDouble() => d.toInt().toString(),
    final DateTime t => '${t.millisecondsSinceEpoch ~/ 1000}',
    final Enum e => e.name,
    _ => '$v',
  };

  String seal(List<Object?> fields) =>
      _hmac.convert(utf8.encode(fields.map(_canon).join('\u001f'))).toString();

  bool verify(String? seal, List<Object?> fields) =>
      seal != null && seal == this.seal(fields);
}
