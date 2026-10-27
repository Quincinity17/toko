import 'package:barcode/barcode.dart';
import 'package:flutter/widgets.dart';

import '../../../core/utils/formatters.dart';
import '../domain/label_barcode.dart';
import '../domain/label_layout.dart';

/// Satu label (hitam di atas putih) berukuran [LabelLayout.labelWidth] ×
/// [LabelLayout.labelHeight] mm, [scale] piksel per mm. Dipakai untuk
/// pratinjau di layar dan cetak langsung ke printer thermal (8 titik/mm).
/// Ukuran huruf sama dengan PDF ([buildLabelPdf]).
class LabelView extends StatelessWidget {
  const LabelView({
    super.key,
    required this.layout,
    required this.options,
    required this.item,
    this.scale = 4,
    this.border,
  });

  final LabelLayout layout;
  final LabelOptions options;
  final LabelItem item;
  final double scale;

  /// Garis tepi (pratinjau saja).
  final BoxBorder? border;

  static const _black = Color(0xFF000000);

  @override
  Widget build(BuildContext context) {
    final h = layout.labelHeight;
    // Ukuran huruf PDF dalam pt (1 mm = 2,835 pt).
    double pt(double v) => v * scale / 2.835;
    final small = pt((h * 0.2).clamp(4.5, 7.0));
    final nameSize = pt((h * 0.27).clamp(5.5, 9.0));
    final priceSize = pt((h * 0.4).clamp(7.0, 14.0));
    final data = options.codeOf(item);
    return Container(
      width: layout.labelWidth * scale,
      height: h * scale,
      padding: EdgeInsets.symmetric(
        horizontal: (h < 25 ? 1.2 : 2) * scale,
        vertical: (h < 25 ? 0.8 : 1.5) * scale,
      ),
      decoration: BoxDecoration(color: const Color(0xFFFFFFFF), border: border),
      child: DefaultTextStyle(
        style: const TextStyle(color: _black, fontFamily: 'Inter'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (options.storeName case final store?)
              Text(
                store,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: small, height: 1.1),
              ),
            if (options.showName)
              Flexible(
                child: Text(
                  item.unitName == null
                      ? item.name
                      : '${item.name} (${item.unitName})',
                  maxLines: h < 25 ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: nameSize, height: 1.1),
                ),
              ),
            if (options.showPrice)
              Text(
                Fmt.rupiah(item.price),
                maxLines: 1,
                style: TextStyle(
                  fontSize: priceSize,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            SizedBox(height: 0.5 * scale),
            Expanded(
              child: Padding(
                // Area kosong kiri-kanan (quiet zone) supaya mudah di-scan.
                padding: EdgeInsets.symmetric(
                  horizontal: layout.labelWidth * 0.07 * scale,
                ),
                child: CustomPaint(
                  painter: _BarcodePainter(data, textSize: small),
                  size: Size.infinite,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarcodePainter extends CustomPainter {
  _BarcodePainter(this.data, {required this.textSize});

  final String data;
  final double textSize;

  @override
  void paint(Canvas canvas, Size size) {
    final code = labelSymbology(data);
    if (code == null || size.height <= 0) return;
    final paint = Paint()..color = const Color(0xFF000000);
    for (final e in code.make(
      data,
      width: size.width,
      height: size.height,
      drawText: true,
      fontHeight: textSize,
    )) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(Rect.fromLTWH(e.left, e.top, e.width, e.height), paint);
      } else if (e is BarcodeText) {
        final tp = TextPainter(
          text: TextSpan(
            text: e.text,
            style: TextStyle(
              fontSize: textSize,
              color: paint.color,
              fontFamily: 'Inter',
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(e.left + (e.width - tp.width) / 2, e.top));
      }
    }
  }

  @override
  bool shouldRepaint(_BarcodePainter old) =>
      old.data != data || old.textSize != textSize;
}
