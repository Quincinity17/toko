import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/formatters.dart';
import '../domain/label_barcode.dart';
import '../domain/label_layout.dart';

/// Membuat PDF label barcode: tiap [LabelItem] dicetak sebanyak `copies`,
/// disusun menurut [layout]. Barcode Code 128 (terbaca semua scanner).
/// [regular]/[bold] = font Inter (nama barang bisa berisi huruf non-Latin);
/// `null` = Helvetica bawaan PDF.
Future<Uint8List> buildLabelPdf({
  required List<LabelItem> items,
  required LabelLayout layout,
  LabelOptions options = const LabelOptions(),
  pw.Font? regular,
  pw.Font? bold,
}) async {
  const mm = PdfPageFormat.mm;
  final doc = pw.Document(
    title: 'Label barang',
    creator: 'Toko',
    theme: regular == null
        ? null
        : pw.ThemeData.withFont(base: regular, bold: bold ?? regular),
  );
  final labels = [
    for (final item in items)
      for (var i = 0; i < item.copies; i++) item,
  ];
  final skip = (options.startAt - 1).clamp(0, layout.perPage - 1);
  final pages = labelPageCount(layout, labels.length, startAt: options.startAt);
  final format = PdfPageFormat(
    layout.pageWidth * mm,
    layout.pageHeight * mm,
    marginAll: 0,
  );

  for (var page = 0; page < pages; page++) {
    final slots = <(int, LabelItem)>[];
    for (var slot = 0; slot < layout.perPage; slot++) {
      final index = page * layout.perPage + slot - skip;
      if (index < 0 || index >= labels.length) continue;
      slots.add((slot, labels[index]));
    }
    doc.addPage(
      pw.Page(
        pageFormat: format,
        build: (_) => pw.Stack(
          children: [
            for (final (slot, item) in slots)
              if (layout.origin(slot) case final o)
                pw.Positioned(
                  left: o.x * mm,
                  top: o.y * mm,
                  child: _label(item, layout, options),
                ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

pw.Widget _label(LabelItem item, LabelLayout layout, LabelOptions options) {
  const mm = PdfPageFormat.mm;
  final h = layout.labelHeight;
  // Ukuran huruf mengikuti tinggi label (pt).
  final small = (h * 0.2).clamp(4.5, 7.0);
  final nameSize = (h * 0.27).clamp(5.5, 9.0);
  final priceSize = (h * 0.4).clamp(7.0, 14.0);
  final data = options.codeOf(item);
  final symbology = labelSymbology(data);

  return pw.Container(
    width: layout.labelWidth * mm,
    height: h * mm,
    padding: pw.EdgeInsets.symmetric(
      horizontal: (h < 25 ? 1.2 : 2) * mm,
      vertical: (h < 25 ? 0.8 : 1.5) * mm,
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (options.storeName case final store?)
          pw.Text(
            store,
            maxLines: 1,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: small),
          ),
        if (options.showName)
          pw.Text(
            item.unitName == null
                ? item.name
                : '${item.name} (${item.unitName})',
            maxLines: h < 25 ? 1 : 2,
            style: pw.TextStyle(fontSize: nameSize),
          ),
        if (options.showPrice)
          pw.Text(
            Fmt.rupiah(item.price),
            style: pw.TextStyle(
              fontSize: priceSize,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        pw.SizedBox(height: 0.5 * mm),
        pw.Expanded(
          child: symbology != null
              // Area kosong kiri-kanan (quiet zone) supaya mudah di-scan.
              ? pw.BarcodeWidget(
                  padding: pw.EdgeInsets.symmetric(
                    horizontal: layout.labelWidth * 0.07 * mm,
                  ),
                  barcode: symbology,
                  data: data,
                  drawText: true,
                  textStyle: pw.TextStyle(fontSize: small),
                )
              : pw.Center(
                  child: pw.Text(data, style: pw.TextStyle(fontSize: nameSize)),
                ),
        ),
      ],
    ),
  );
}
