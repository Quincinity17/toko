import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/printer_config.dart';
import 'android_bluetooth.dart';
import 'printer_failure.dart';
import 'windows_serial.dart';
import 'windows_spooler.dart';

/// Mengirim byte ESC/POS ke printer. Di-override di tes.
abstract interface class PrinterTransport {
  /// Nama printer yang terpasang di sistem.
  Future<List<String>> listPrinters();

  /// Port serial yang ada (termasuk port Bluetooth yang sudah dipasangkan).
  Future<List<String>> listSerialPorts();

  Future<void> send(PrinterConfig config, Uint8List data, {String jobName});

  /// Memastikan printer bisa dihubungi tanpa mencetak apa pun. Melempar
  /// [PrinterFailure] dengan penjelasan bila gagal.
  Future<void> check(PrinterConfig config);
}

/// - Printer terpasang: Windows lewat spooler (RAW), macOS/Linux lewat `lp`.
/// - Jaringan: koneksi TCP langsung ke printer (biasanya port 9100).
/// - Bluetooth/serial: port COM (Windows) atau `/dev/…` (macOS/Linux);
///   Android: printer Bluetooth yang dipasangkan ([AndroidBluetooth]).
class DefaultPrinterTransport implements PrinterTransport {
  const DefaultPrinterTransport();

  static const _timeout = Duration(seconds: 5);

  @override
  Future<List<String>> listPrinters() async {
    if (Platform.isWindows) return Isolate.run(windowsPrinterNames);
    if (Platform.isMacOS || Platform.isLinux) {
      try {
        final r = await Process.run('lpstat', ['-e']);
        if (r.exitCode != 0) return const [];
        return [
          for (final l in (r.stdout as String).split('\n'))
            if (l.trim().isNotEmpty) l.trim(),
        ];
      } on ProcessException {
        return const [];
      }
    }
    return const [];
  }

  @override
  Future<List<String>> listSerialPorts() async {
    if (Platform.isAndroid) return AndroidBluetooth.bondedDevices();
    if (Platform.isWindows) {
      // Daftar port COM dari registry (termasuk "Serial over Bluetooth").
      try {
        final r = await Process.run('reg', [
          'query',
          r'HKLM\HARDWARE\DEVICEMAP\SERIALCOMM',
        ]);
        final ports = {
          for (final m in RegExp(
            r'REG_SZ\s+(COM\d+)',
          ).allMatches(r.stdout as String))
            m.group(1)!,
        }.toList();
        ports.sort(
          (a, b) =>
              int.parse(a.substring(3)).compareTo(int.parse(b.substring(3))),
        );
        return ports;
      } on ProcessException {
        return const [];
      }
    }
    final dev = Directory('/dev');
    if (!dev.existsSync()) return const [];
    final pattern = Platform.isMacOS
        ? RegExp(r'^cu\.')
        : RegExp(r'^(ttyUSB|ttyACM|rfcomm|ttyS)\d+$');
    return [
      for (final e in dev.listSync())
        if (pattern.hasMatch(e.uri.pathSegments.last)) e.path,
    ]..sort();
  }

  @override
  Future<void> send(
    PrinterConfig config,
    Uint8List data, {
    String jobName = 'Struk',
  }) async {
    _requireReady(config);
    switch (config.connection) {
      case PrinterConnection.none:
        return;
      case PrinterConnection.system:
        await _sendToSystem(config.printerName, data, jobName);
      case PrinterConnection.network:
        await _sendToNetwork(config.host, config.port, data);
      case PrinterConnection.serial:
        await _sendToSerial(config.serialPort, config.baudRate, data);
    }
  }

  @override
  Future<void> check(PrinterConfig config) async {
    _requireReady(config);
    switch (config.connection) {
      case PrinterConnection.none:
        return;
      case PrinterConnection.system:
        final names = await listPrinters();
        if (!names.contains(config.printerName)) {
          throw PrinterFailure(
            'Printer "${config.printerName}" tidak ada di komputer ini.',
          );
        }
      case PrinterConnection.network:
        // Sambung lalu putus tanpa mengirim data.
        await _sendToNetwork(config.host, config.port, Uint8List(0));
      case PrinterConnection.serial:
        await _sendToSerial(config.serialPort, config.baudRate, Uint8List(0));
    }
  }

  static void _requireReady(PrinterConfig config) {
    if (!config.isReady) {
      throw const PrinterFailure(
        'Printer belum diatur. Atur lewat tombol Printer Nota di layar Kasir.',
      );
    }
  }

  Future<void> _sendToSystem(String name, Uint8List data, String job) async {
    if (Platform.isWindows) {
      return Isolate.run(() => windowsWriteRaw(name, data, job));
    }
    if (Platform.isMacOS || Platform.isLinux) {
      final Process p;
      try {
        p = await Process.start('lp', ['-d', name, '-t', job, '-o', 'raw']);
      } on ProcessException {
        throw const PrinterFailure(
          'Perintah cetak sistem (lp) tidak tersedia.',
        );
      }
      p.stdin.add(data);
      await p.stdin.close();
      final err = await p.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      if (await p.exitCode != 0) {
        throw PrinterFailure(
          'Gagal mencetak ke "$name"${err.trim().isEmpty ? '' : ': ${err.trim()}'}',
        );
      }
      return;
    }
    throw const PrinterFailure(
      'Printer terpasang belum didukung di perangkat ini. Pakai printer '
      'jaringan (LAN) atau Bluetooth.',
    );
  }

  Future<void> _sendToNetwork(String host, int port, Uint8List data) async {
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: _timeout);
      if (data.isNotEmpty) {
        socket.add(data);
        await socket.flush().timeout(_timeout);
      }
    } on SocketException {
      throw PrinterFailure(
        'Printer di $host:$port tidak bisa dihubungi. Pastikan printer '
        'menyala dan satu jaringan dengan komputer ini.',
      );
    } on Exception {
      throw PrinterFailure('Gagal mengirim data ke printer $host:$port.');
    } finally {
      socket?.destroy();
    }
  }

  Future<void> _sendToSerial(String port, int baud, Uint8List data) async {
    if (Platform.isAndroid) return AndroidBluetooth.send(port, data);
    if (Platform.isWindows) {
      return Isolate.run(() => windowsWriteSerial(port, baud, data));
    }
    // macOS/Linux: atur baud dengan stty, lalu tulis ke file perangkat.
    try {
      await Process.run('stty', [
        Platform.isMacOS ? '-f' : '-F',
        port,
        '$baud',
        'cs8',
        '-cstopb',
        '-parenb',
      ]);
    } on ProcessException {
      // Tanpa stty: pakai pengaturan port yang ada.
    }
    RandomAccessFile? file;
    try {
      file = await File(port)
          .open(mode: FileMode.writeOnlyAppend)
          .timeout(_timeout);
      if (data.isNotEmpty) await file.writeFrom(data).timeout(_timeout);
    } on Exception {
      throw PrinterFailure(
        'Port $port tidak bisa dibuka. Pastikan printer menyala dan sudah '
        'dipasangkan (Bluetooth).',
      );
    } finally {
      await file?.close();
    }
  }
}

final printerTransportProvider = Provider<PrinterTransport>(
  (ref) => const DefaultPrinterTransport(),
);
