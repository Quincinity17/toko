import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../receipt/data/printer_failure.dart';
import '../../receipt/data/printer_transport.dart';
import '../../receipt/data/receipt_renderer.dart';
import '../../receipt/data/receipt_settings_repository.dart';
import '../../receipt/domain/escpos.dart';
import '../domain/label_layout.dart';
import '../presentation/label_view.dart';

/// Mengubah widget label menjadi gambar hitam-putih selebar [width] titik.
typedef LabelRasterizer = Future<MonoBitmap> Function(Widget, double width);

Future<MonoBitmap> _rasterize(Widget widget, double width) async {
  final image = await renderWidgetToImage(widget, width: width);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return MonoBitmap.fromRgba(
      data!.buffer.asUint8List(),
      image.width,
      image.height,
    );
  } finally {
    image.dispose();
  }
}

/// Mencetak label langsung ke printer nota (thermal ESC/POS) yang diatur di
/// kasir: label disusun ke bawah (untuk kertas stiker rol 58/80 mm). Lebar
/// label mengikuti ukuran yang dipilih (8 titik/mm), diperkecil bila lebih
/// lebar dari kertas.
class LabelPrinter {
  LabelPrinter(this._settings, this._transport, {LabelRasterizer? rasterize})
    : _render = rasterize ?? _rasterize;

  final ReceiptSettingsRepository _settings;
  final PrinterTransport _transport;
  final LabelRasterizer _render;

  static const dotsPerMm = 8.0;

  Future<void> print(
    List<LabelItem> items,
    LabelLayout layout,
    LabelOptions options,
  ) async {
    final config = await _settings.printer();
    if (!config.isReady) {
      throw const PrinterFailure(
        'Printer belum diatur. Atur lewat tombol Printer Nota di layar Kasir.',
      );
    }
    if (items.isEmpty) return;
    final paper = config.paperWidth.dots.toDouble();
    final scale = math.min(dotsPerMm, paper / layout.labelWidth);
    final width = layout.labelWidth * scale;
    final p = EscPos()..init();
    for (final item in items) {
      // Satu gambar per barang, dicetak sebanyak jumlah labelnya.
      final image = await _render(
        LabelView(layout: layout, options: options, item: item, scale: scale),
        width,
      );
      for (var i = 0; i < item.copies; i++) {
        p
          ..raster(image)
          ..feed(1);
      }
    }
    p.feed(config.feedLines);
    if (config.autoCut) p.cut();
    await _transport.send(config, p.bytes, jobName: 'Label barang');
  }
}

final labelPrinterProvider = Provider<LabelPrinter>(
  (ref) => LabelPrinter(
    ref.watch(receiptSettingsRepositoryProvider),
    ref.watch(printerTransportProvider),
  ),
);
