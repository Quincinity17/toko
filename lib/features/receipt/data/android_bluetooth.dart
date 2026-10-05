import 'package:flutter/services.dart';

import 'printer_failure.dart';

/// Printer thermal Bluetooth (SPP) di Android, lewat kode native
/// `MainActivity.kt` (kanal `id.toko/bluetooth`). Hanya perangkat yang sudah
/// dipasangkan di Pengaturan Bluetooth HP.
abstract final class AndroidBluetooth {
  static const _channel = MethodChannel('id.toko/bluetooth');

  /// Alamat MAC di dalam teks port, mis. "RPP02N (66:22:AA:BB:CC:DD)".
  static final _mac = RegExp(r'([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}');

  static String? macOf(String port) => _mac.firstMatch(port)?.group(0);

  /// Perangkat terpasang sebagai "Nama (MAC)" — disimpan apa adanya di
  /// `PrinterConfig.serialPort`, MAC diambil saat mengirim.
  static Future<List<String>> bondedDevices() async {
    try {
      final list =
          await _channel.invokeListMethod<Map<Object?, Object?>>(
            'bondedDevices',
          ) ??
          const [];
      return [for (final d in list) '${d['name']} (${d['address']})'];
    } on PlatformException catch (e) {
      throw PrinterFailure(e.message ?? 'Bluetooth tidak bisa dipakai.');
    }
  }

  /// Mengirim [data] (kosong = hanya cek sambungan).
  static Future<void> send(String port, Uint8List data) async {
    final mac = macOf(port);
    if (mac == null) {
      throw const PrinterFailure(
        'Pilih printer Bluetooth dari daftar perangkat yang dipasangkan.',
      );
    }
    try {
      await _channel.invokeMethod<void>('send', {
        'address': mac,
        'bytes': data,
      });
    } on PlatformException catch (e) {
      throw PrinterFailure(e.message ?? 'Gagal mengirim ke printer.');
    }
  }
}
