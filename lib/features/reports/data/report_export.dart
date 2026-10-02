import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../../core/utils/formatters.dart';
import '../../sales/domain/sale.dart';
import '../domain/report_models.dart';

/// Laporan lengkap satu rentang dalam satu file Excel, satu sheet per
/// bagian. Angka dalam sel berupa angka (bukan teks) supaya bisa dihitung
/// ulang di Excel.
Uint8List exportReportXlsx({
  required ReportBundle bundle,
  required InventorySummary inventory,
  required List<StockStatus> stock,
  required List<SaleSummary> invoices,
}) {
  final book = Excel.createExcel();
  final first = book.getDefaultSheet() ?? 'Sheet1';
  book.rename(first, 'Ringkasan');
  book.setDefaultSheet('Ringkasan');

  CellValue cell(Object? v) => switch (v) {
    null => TextCellValue(''),
    int() => IntCellValue(v),
    double() =>
      v == v.roundToDouble() ? IntCellValue(v.round()) : DoubleCellValue(v),
    _ => TextCellValue('$v'),
  };

  void sheet(
    String name,
    List<String> headers,
    List<List<Object?>> rows, {
    List<double>? widths,
  }) {
    final s = book[name];
    s.appendRow([for (final h in headers) TextCellValue(h)]);
    for (final r in rows) {
      s.appendRow([for (final v in r) cell(v)]);
    }
    for (var i = 0; i < headers.length; i++) {
      s.setColumnWidth(i, widths != null && i < widths.length ? widths[i] : 16);
    }
  }

  double? pct(double? ratio) =>
      ratio == null ? null : (ratio * 1000).round() / 10;

  final s = bundle.summary, p = bundle.previous;
  sheet(
    'Ringkasan',
    ['Keterangan', 'Periode ini', 'Periode sebelumnya', 'Perubahan (%)'],
    [
      ['Periode', bundle.range.label, bundle.range.previous.label, null],
      [
        'Penjualan kotor',
        s.grossSales,
        p.grossSales,
        pct(growth(s.grossSales, p.grossSales)),
      ],
      ['Potongan', s.discount, p.discount, pct(growth(s.discount, p.discount))],
      ['Omzet bersih', s.revenue, p.revenue, pct(growth(s.revenue, p.revenue))],
      ['Harga pokok terjual', s.cost, p.cost, pct(growth(s.cost, p.cost))],
      [
        'Laba kotor',
        s.grossProfit,
        p.grossProfit,
        pct(growth(s.grossProfit, p.grossProfit)),
      ],
      ['Margin laba kotor (%)', pct(s.margin), pct(p.margin), null],
      [
        'Jumlah transaksi',
        s.transactions,
        p.transactions,
        pct(growth(s.transactions, p.transactions)),
      ],
      [
        'Rata-rata belanja',
        s.averageBasket,
        p.averageBasket,
        pct(growth(s.averageBasket, p.averageBasket)),
      ],
      [
        'Barang per transaksi',
        (s.itemsPerTransaction * 10).round() / 10,
        (p.itemsPerTransaction * 10).round() / 10,
        null,
      ],
      [],
      ['Nilai persediaan (harga beli)', inventory.costValue, null, null],
      [
        'Potensi omzet persediaan (harga jual)',
        inventory.retailValue,
        null,
        null,
      ],
    ],
    widths: [36, 20, 22, 16],
  );

  sheet(
    'Harian',
    ['Tanggal', 'Transaksi', 'Omzet', 'Harga pokok', 'Laba kotor'],
    [
      for (final d in bundle.daily)
        [
          Fmt.dateShort(d.date),
          d.transactions,
          d.revenue,
          d.cost,
          d.grossProfit,
        ],
    ],
  );

  sheet(
    'Per Jam',
    ['Jam', 'Transaksi', 'Omzet'],
    [
      for (final b in bundle.byHour)
        [
          '${b.bucket.toString().padLeft(2, '0')}:00',
          b.transactions,
          b.revenue,
        ],
    ],
  );

  sheet(
    'Per Hari',
    ['Hari', 'Transaksi', 'Omzet'],
    [
      for (final b in bundle.byWeekday)
        [weekdayNames[b.bucket], b.transactions, b.revenue],
    ],
  );

  sheet(
    'Produk',
    [
      'Kode',
      'Nama',
      'Kategori',
      'Kelas ABC',
      'Terjual',
      'Satuan',
      'Omzet',
      'Harga pokok',
      'Laba kotor',
      'Margin (%)',
      'Transaksi',
    ],
    [
      for (final p in bundle.products)
        [
          p.code,
          p.name,
          p.category,
          p.abc?.label,
          p.quantity,
          p.unit,
          p.revenue,
          p.cost,
          p.grossProfit,
          pct(p.margin),
          p.transactions,
        ],
    ],
    widths: [12, 36, 18, 10, 10, 8, 14, 14, 14, 10, 10],
  );

  List<List<Object?>> groupRows(List<GroupPerformance> list) => [
    for (final g in list)
      [g.name, g.transactions, g.revenue, g.cost, g.grossProfit, pct(g.margin)],
  ];
  const groupHeaders = [
    'Transaksi',
    'Omzet',
    'Harga pokok',
    'Laba kotor',
    'Margin (%)',
  ];

  sheet('Kategori', [
    'Kategori',
    ...groupHeaders,
  ], groupRows(bundle.categories));
  sheet('Pembayaran', ['Metode', ...groupHeaders], groupRows(bundle.payments));
  if (bundle.stores.length > 1) {
    sheet('Toko', ['Toko', ...groupHeaders], groupRows(bundle.stores));
  }
  sheet('Kasir', ['Kasir', ...groupHeaders], groupRows(bundle.cashiers));
  sheet('Terminal', ['Terminal', ...groupHeaders], groupRows(bundle.terminals));

  sheet(
    'Stok',
    [
      'Kode',
      'Nama',
      'Stok',
      'Satuan',
      'Harga beli',
      'Nilai (modal)',
      'Rata-rata terjual/hari (30 hari)',
      'Perkiraan habis (hari)',
      'Terakhir terjual',
    ],
    [
      for (final st in stock)
        [
          st.code,
          st.name,
          st.stock,
          st.unit,
          st.purchasePrice,
          st.value,
          (st.averageDailySales * 100).round() / 100,
          st.daysOfCover?.round(),
          st.lastSold == null ? 'Belum pernah' : Fmt.dateShort(st.lastSold!),
        ],
    ],
    widths: [12, 36, 10, 8, 12, 14, 16, 14, 16],
  );

  sheet(
    'Faktur',
    [
      'No. Faktur',
      'Waktu',
      'Kasir',
      'Barang',
      'Subtotal',
      'Potongan',
      'Total',
      'Metode bayar',
      'Dibayar',
      'Kembalian',
    ],
    [
      for (final f in invoices)
        [
          f.invoiceNo,
          Fmt.dateTime(f.date),
          f.cashierName,
          f.itemCount,
          f.subtotal,
          f.discount,
          f.total,
          f.paymentMethod,
          f.paid,
          f.change,
        ],
    ],
    widths: [24, 18, 18, 8, 12, 12, 12, 12, 16, 12, 12],
  );

  return Uint8List.fromList(book.encode()!);
}
