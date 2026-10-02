import 'dart:typed_data';

import 'package:toko/features/receipt/data/printer_failure.dart';
import 'package:toko/features/receipt/data/printer_transport.dart';
import 'package:toko/features/receipt/data/receipt_renderer.dart';
import 'package:toko/features/receipt/domain/escpos.dart';
import 'package:toko/features/receipt/domain/printer_config.dart';

/// Mencatat byte yang dikirim, tanpa printer sungguhan.
class FakeTransport implements PrinterTransport {
  final jobs = <Uint8List>[];
  final checked = <PrinterConfig>[];

  @override
  Future<List<String>> listPrinters() async => ['Thermal 58'];

  @override
  Future<List<String>> listSerialPorts() async => ['COM3', 'COM5'];

  @override
  Future<void> check(PrinterConfig config) async {
    if (!config.isReady) throw const PrinterFailure('Printer belum diatur.');
    checked.add(config);
  }

  @override
  Future<void> send(
    PrinterConfig config,
    Uint8List data, {
    String jobName = '',
  }) async {
    if (!config.isReady) throw const PrinterFailure('Printer belum diatur.');
    jobs.add(data);
  }
}

/// Mencatat HTML yang akan dicetak dan mengembalikan gambar kecil, tanpa
/// merender (render di luar layar butuh waktu nyata, bukan fake async).
class FakeRasterizer implements ReceiptRasterizer {
  final html = <String>[];
  final widths = <PaperWidth>[];

  @override
  Future<MonoBitmap> rasterize(String source, PaperWidth paperWidth) async {
    html.add(source);
    widths.add(paperWidth);
    return MonoBitmap(paperWidth.dots, 2)..setBlack(0, 0);
  }
}
