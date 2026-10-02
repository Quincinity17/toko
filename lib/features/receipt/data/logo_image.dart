import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/printer_config.dart';
import '../domain/receipt_template.dart';
import 'printer_failure.dart';

/// Menyiapkan file logo untuk disimpan di bentuk struk: dicek, diperkecil
/// bila lebih lebar dari kertas 80 mm (576 titik), lalu disimpan sebagai PNG
/// data URI. Jadi file besar (foto/logo resolusi tinggi) tetap bisa dipakai
/// tanpa membuat database membengkak.
Future<String> logoToDataUri(Uint8List bytes) async {
  if (bytes.length > ReceiptTemplate.maxLogoBytes) {
    throw const PrinterFailure('Ukuran file logo maksimal 5 MB.');
  }
  final ui.Codec probe;
  try {
    probe = await ui.instantiateImageCodec(bytes);
  } catch (_) {
    throw const PrinterFailure('File bukan gambar PNG/JPG yang valid.');
  }
  final first = await probe.getNextFrame();
  final width = first.image.width;
  first.image.dispose();
  probe.dispose();

  final maxWidth = PaperWidth.mm80.dots;
  final codec = width > maxWidth
      ? await ui.instantiateImageCodec(bytes, targetWidth: maxWidth)
      : await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  try {
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    return 'data:image/png;base64,${base64Encode(png!.buffer.asUint8List())}';
  } finally {
    frame.image.dispose();
    codec.dispose();
  }
}
