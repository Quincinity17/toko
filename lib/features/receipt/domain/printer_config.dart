import 'package:flutter/foundation.dart';

/// Lebar kertas printer thermal dan jumlah titik (dot) cetaknya pada
/// 203 dpi. Struk dirender selebar [dots] piksel lalu dicetak sebagai gambar.
enum PaperWidth {
  mm58('58 mm', 384),
  mm80('80 mm', 576);

  const PaperWidth(this.label, this.dots);

  final String label;
  final int dots;
}

/// Cara aplikasi mengirim struk ke printer.
enum PrinterConnection {
  /// Belum diatur: struk tidak dicetak.
  none('Tidak ada'),

  /// Printer yang terpasang di sistem (Windows: Devices & Printers, USB).
  /// Data ESC/POS dikirim mentah (RAW) lewat spooler.
  system('Printer terpasang'),

  /// Printer LAN/WiFi lewat port 9100.
  network('Jaringan (LAN)'),

  /// Port serial: printer Bluetooth (di Windows muncul sebagai port COM
  /// "Standard Serial over Bluetooth link" setelah dipasangkan), atau kabel
  /// serial/USB-serial.
  serial('Bluetooth / Serial');

  const PrinterConnection(this.label);

  final String label;
}

/// Pengaturan printer komputer ini. Disimpan di tabel `settings` (lokal per
/// komputer, karena printer menempel ke komputernya). Boleh diubah semua
/// peran dari layar Kasir.
@immutable
class PrinterConfig {
  const PrinterConfig({
    this.connection = PrinterConnection.none,
    this.paperWidth = PaperWidth.mm58,
    this.printerName = '',
    this.host = '',
    this.port = defaultPort,
    this.serialPort = '',
    this.baudRate = defaultBaudRate,
    this.autoPrint = true,
    this.autoCut = true,
    this.openDrawer = true,
    this.drawerPin = 2,
    this.feedLines = 3,
  });

  static const defaultPort = 9100;
  static const defaultBaudRate = 9600;

  /// Baud rate yang umum dipakai printer thermal serial/Bluetooth.
  static const baudRates = [9600, 19200, 38400, 57600, 115200];

  /// Batas baris kosong sebelum kertas dipotong.
  static const maxFeedLines = 8;

  final PrinterConnection connection;

  /// Lebar kertas yang terpasang di printer ini.
  final PaperWidth paperWidth;

  /// Nama printer di sistem (untuk [PrinterConnection.system]).
  final String printerName;

  /// Alamat IP printer (untuk [PrinterConnection.network]).
  final String host;
  final int port;

  /// Port serial, mis. `COM5` (Windows) atau `/dev/cu.Printer` (macOS).
  final String serialPort;
  final int baudRate;

  /// Struk langsung dicetak setelah transaksi selesai.
  final bool autoPrint;

  /// Kertas dipotong otomatis (diabaikan printer tanpa pemotong).
  final bool autoCut;

  /// Laci uang dibuka saat transaksi tunai selesai.
  final bool openDrawer;

  /// Pin konektor laci di printer: 2 (umum) atau 5.
  final int drawerPin;

  /// Baris kosong di akhir agar tulisan terakhir melewati pisau pemotong.
  final int feedLines;

  /// Printer sudah diatur cukup lengkap untuk dipakai.
  bool get isReady => switch (connection) {
    PrinterConnection.none => false,
    PrinterConnection.system => printerName.isNotEmpty,
    PrinterConnection.network => host.isNotEmpty,
    PrinterConnection.serial => serialPort.isNotEmpty,
  };

  /// Ringkasan untuk ditampilkan di daftar pengaturan.
  String get summary => switch (connection) {
    PrinterConnection.none => 'Belum diatur',
    PrinterConnection.system =>
      printerName.isEmpty ? 'Pilih printer' : printerName,
    PrinterConnection.network => host.isEmpty ? 'Isi alamat IP' : '$host:$port',
    PrinterConnection.serial =>
      serialPort.isEmpty ? 'Pilih port' : '$serialPort · $baudRate',
  };

  PrinterConfig copyWith({
    PrinterConnection? connection,
    PaperWidth? paperWidth,
    String? printerName,
    String? host,
    int? port,
    String? serialPort,
    int? baudRate,
    bool? autoPrint,
    bool? autoCut,
    bool? openDrawer,
    int? drawerPin,
    int? feedLines,
  }) => PrinterConfig(
    connection: connection ?? this.connection,
    paperWidth: paperWidth ?? this.paperWidth,
    printerName: printerName ?? this.printerName,
    host: host ?? this.host,
    port: port ?? this.port,
    serialPort: serialPort ?? this.serialPort,
    baudRate: baudRate ?? this.baudRate,
    autoPrint: autoPrint ?? this.autoPrint,
    autoCut: autoCut ?? this.autoCut,
    openDrawer: openDrawer ?? this.openDrawer,
    drawerPin: drawerPin ?? this.drawerPin,
    feedLines: feedLines ?? this.feedLines,
  );

  Map<String, Object?> toJson() => {
    'connection': connection.name,
    'paperWidth': paperWidth.name,
    'printerName': printerName,
    'host': host,
    'port': port,
    'serialPort': serialPort,
    'baudRate': baudRate,
    'autoPrint': autoPrint,
    'autoCut': autoCut,
    'openDrawer': openDrawer,
    'drawerPin': drawerPin,
    'feedLines': feedLines,
  };

  factory PrinterConfig.fromJson(Map<String, Object?> json) {
    const d = PrinterConfig();
    bool b(String k, bool fallback) =>
        json[k] is bool ? json[k]! as bool : fallback;
    String s(String k) => json[k] is String ? json[k]! as String : '';
    final port = json['port'];
    final feed = json['feedLines'];
    return PrinterConfig(
      connection:
          PrinterConnection.values.asNameMap()[json['connection']] ??
          d.connection,
      paperWidth:
          PaperWidth.values.asNameMap()[json['paperWidth']] ?? d.paperWidth,
      printerName: s('printerName'),
      host: s('host'),
      port: port is int && port > 0 && port < 65536 ? port : d.port,
      serialPort: s('serialPort'),
      baudRate: baudRates.contains(json['baudRate'])
          ? json['baudRate']! as int
          : d.baudRate,
      autoPrint: b('autoPrint', d.autoPrint),
      autoCut: b('autoCut', d.autoCut),
      openDrawer: b('openDrawer', d.openDrawer),
      drawerPin: json['drawerPin'] == 5 ? 5 : 2,
      feedLines: feed is int ? feed.clamp(0, maxFeedLines) : d.feedLines,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PrinterConfig && mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);
}
