import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toko/features/receipt/data/logo_image.dart';
import 'package:toko/features/receipt/data/printer_failure.dart';
import 'package:toko/features/receipt/data/receipt_renderer.dart';
import 'package:toko/features/receipt/domain/receipt.dart';
import 'package:toko/features/receipt/domain/printer_config.dart';
import 'package:toko/features/receipt/domain/receipt_html.dart';
import 'package:toko/features/receipt/domain/receipt_template.dart';

/// Render sungguhan di luar layar (butuh waktu nyata → `runAsync`).
void main() {
  testWidgets('template bawaan dirender jadi gambar selebar kertas, '
      'logo ikut tergambar', (tester) async {
    // Font asli (bukan font kotak bawaan tes) supaya ukuran teks realistis.
    await tester.runAsync(() async {
      final loader = FontLoader('Inter');
      for (final w in ['Regular', 'Bold']) {
        final bytes = File('assets/fonts/Inter/Inter-$w.ttf').readAsBytesSync();
        loader.addFont(Future.value(ByteData.sublistView(bytes)));
      }
      await loader.load();
    });
    await tester.pump();

    await tester.runAsync(() async {
      // Logo contoh: kotak hitam 120×60 sebagai PNG data URI.
      final logoImg = await renderWidgetToImage(
        Container(width: 120, height: 60, color: const Color(0xFF000000)),
        width: 120,
      );
      final png = await logoImg.toByteData(format: ui.ImageByteFormat.png);
      final logo =
          'data:image/png;base64,${base64Encode(png!.buffer.asUint8List())}';

      const rasterizer = WidgetReceiptRasterizer();
      Future<int> heightFor(PaperWidth w, {String? logo}) async {
        final html = ReceiptHtml.render(
          const ReceiptTemplate().html,
          ReceiptData.sample().toTemplateValues(logo: logo),
        );
        final bmp = await rasterizer.rasterize(html, w);
        expect(bmp.width, w.dots);
        expect(bmp.bytes.any((b) => b != 0), isTrue);
        return bmp.height;
      }

      final plain = await heightFor(PaperWidth.mm58);
      final withLogo = await heightFor(PaperWidth.mm58, logo: logo);
      expect(plain, greaterThan(300));
      expect(withLogo, greaterThanOrEqualTo(plain + 60));
      await heightFor(PaperWidth.mm80);
    });
  });

  testWidgets('logo besar diperkecil ke lebar kertas 80 mm; file bukan '
      'gambar atau > 5 MB ditolak', (tester) async {
    await tester.runAsync(() async {
      Future<Uint8List> png(double w, double h) async {
        final img = await renderWidgetToImage(
          Container(width: w, height: h, color: const Color(0xFF000000)),
          width: w,
        );
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      }

      Future<int> widthOf(String dataUri) async {
        final bytes = base64Decode(dataUri.split(',').last);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        return frame.image.width;
      }

      final big = await logoToDataUri(await png(1200, 300));
      expect(big, startsWith('data:image/png;base64,'));
      expect(await widthOf(big), 576);
      final small = await logoToDataUri(await png(200, 80));
      expect(await widthOf(small), 200);

      await expectLater(
        logoToDataUri(Uint8List.fromList(utf8.encode('bukan gambar'))),
        throwsA(isA<PrinterFailure>()),
      );
      await expectLater(
        logoToDataUri(Uint8List(ReceiptTemplate.maxLogoBytes + 1)),
        throwsA(isA<PrinterFailure>()),
      );
    });
  });
}
