import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/charts.dart';
import '../../../core/widgets/data_table_card.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/stat_card.dart';
import '../../sales/domain/sale.dart';
import '../../sales/presentation/widgets/sale_detail_sheet.dart';
import '../domain/report_models.dart';

/// Kartu-kartu angka dalam grid responsif (4 / 2 / 1 kolom).
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1000
            ? 4
            : constraints.maxWidth > 560
            ? 2
            : 1;
        const gap = AppSpacing.md;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

/// Judul bagian kecil di atas kartu/tabel.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.headline.copyWith(color: c.label)),
          if (subtitle != null)
            Text(
              subtitle!,
              style: AppTypography.footnote.copyWith(color: c.labelSecondary),
            ),
        ],
      ),
    );
  }
}

const _gap = SizedBox(height: AppSpacing.xl);

String _pct(double? r) => r == null ? '–' : Fmt.percent(r);

// -----------------------------------------------------------------------------
// 1. Ringkasan
// -----------------------------------------------------------------------------

class SummarySection extends StatelessWidget {
  const SummarySection({super.key, required this.bundle});

  final ReportBundle bundle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = bundle.summary, p = bundle.previous;
    final vs = 'vs ${bundle.range.previous.label}';
    final top = [...bundle.products]
      ..sort((a, b) => b.grossProfit.compareTo(a.grossProfit));
    final aCount = bundle.products.where((x) => x.abc == AbcClass.a).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          cards: [
            StatCard(
              label: 'Omzet bersih',
              value: Fmt.rupiah(s.revenue),
              icon: CupertinoIcons.money_dollar_circle_fill,
              color: c.accent,
              delta: growth(s.revenue, p.revenue),
              deltaLabel: vs,
              caption: 'Periode lalu ${Fmt.rupiah(p.revenue)}',
            ),
            StatCard(
              label: 'Laba kotor',
              value: Fmt.rupiah(s.grossProfit),
              icon: CupertinoIcons.chart_pie_fill,
              color: c.chart2,
              delta: growth(s.grossProfit, p.grossProfit),
              deltaLabel: vs,
              caption: 'Periode lalu ${Fmt.rupiah(p.grossProfit)}',
            ),
            StatCard(
              label: 'Margin laba kotor',
              value: _pct(s.margin),
              icon: CupertinoIcons.percent,
              color: c.chart2,
              caption: 'Periode lalu ${_pct(p.margin)}',
            ),
            StatCard(
              label: 'Transaksi',
              value: Fmt.number(s.transactions),
              icon: CupertinoIcons.doc_text_fill,
              color: c.accent,
              delta: growth(s.transactions, p.transactions),
              deltaLabel: vs,
              caption: 'Periode lalu ${Fmt.number(p.transactions)}',
            ),
            StatCard(
              label: 'Rata-rata belanja',
              value: Fmt.rupiah(s.averageBasket),
              icon: CupertinoIcons.cart_fill,
              color: c.accent,
              delta: growth(s.averageBasket, p.averageBasket),
              deltaLabel: vs,
              caption: 'Periode lalu ${Fmt.rupiah(p.averageBasket)}',
            ),
            StatCard(
              label: 'Barang per transaksi',
              value: Fmt.number((s.itemsPerTransaction * 10).round() / 10),
              icon: CupertinoIcons.cube_box_fill,
              color: c.accent,
              caption: 'Total ${Fmt.number(s.quantity)} barang terjual',
            ),
          ],
        ),
        _gap,
        InsetGroupedSection(
          header: 'Rincian laba',
          footer:
              'Harga pokok = jumlah terjual × harga beli saat barang terjual. '
              'Laba bersih (laba kotor dikurangi sewa, gaji, listrik, dll.) '
              'butuh fitur pencatatan pengeluaran, belum tersedia.',
          children: [
            // Potongan hanya ada pada faktur lama (fitur voucher dihapus).
            if (s.discount > 0) ...[
              InsetGroupedTile(
                title: 'Penjualan kotor',
                value: Fmt.rupiah(s.grossSales),
              ),
              InsetGroupedTile(
                title: '− Potongan',
                value: Fmt.rupiah(s.discount),
              ),
            ],
            InsetGroupedTile(
              title: s.discount > 0 ? '= Omzet bersih' : 'Omzet',
              value: Fmt.rupiah(s.revenue),
            ),
            InsetGroupedTile(
              title: '− Harga pokok terjual',
              value: Fmt.rupiah(s.cost),
            ),
            InsetGroupedTile(
              title: '= Laba kotor',
              value: Fmt.rupiah(s.grossProfit),
            ),
          ],
        ),
        _gap,
        InsetGroupedSection(
          header: 'Sorotan',
          children: [
            InsetGroupedTile(
              leading: TileIcon(
                icon: CupertinoIcons.clock_fill,
                color: c.accent,
              ),
              title: 'Jam paling ramai',
              value: bundle.busiestHour == null
                  ? '–'
                  : '${bundle.busiestHour!.bucket.toString().padLeft(2, '0')}:00–'
                        '${(bundle.busiestHour!.bucket + 1).toString().padLeft(2, '0')}:00',
            ),
            InsetGroupedTile(
              leading: TileIcon(icon: CupertinoIcons.calendar, color: c.accent),
              title: 'Hari paling ramai',
              value: bundle.busiestWeekday == null
                  ? '–'
                  : weekdayNames[bundle.busiestWeekday!.bucket],
            ),
            InsetGroupedTile(
              leading: TileIcon(
                icon: CupertinoIcons.star_fill,
                color: c.chart2,
              ),
              title: 'Penyumbang laba terbesar',
              subtitle: top.isEmpty
                  ? null
                  : 'Laba ${Fmt.rupiah(top.first.grossProfit)}',
              value: top.isEmpty ? '–' : top.first.name,
            ),
            InsetGroupedTile(
              leading: TileIcon(
                icon: CupertinoIcons.chart_bar_alt_fill,
                color: c.chart2,
              ),
              title: 'Barang kelas A (±80% laba)',
              value: bundle.products.isEmpty
                  ? '–'
                  : '$aCount dari ${bundle.products.length} barang terjual',
            ),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 2. Tren
// -----------------------------------------------------------------------------

class TrendSection extends StatelessWidget {
  const TrendSection({super.key, required this.bundle});

  final ReportBundle bundle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final days = bundle.daily;
    final multiDay = days.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (multiDay) ...[
          const SectionTitle(
            'Omzet dan laba kotor per hari',
            subtitle: 'Arahkan kursor ke grafik untuk melihat angka per hari.',
          ),
          AppCard(
            child: TrendLineChart(
              series: [
                ChartSeries(
                  label: 'Omzet',
                  color: c.accent,
                  values: [for (final d in days) d.revenue],
                ),
                ChartSeries(
                  label: 'Laba kotor',
                  color: c.chart2,
                  values: [for (final d in days) d.grossProfit],
                ),
              ],
              xLabels: [for (final d in days) Fmt.dayShort(d.date)],
            ),
          ),
          _gap,
        ],
        const SectionTitle(
          'Omzet per jam',
          subtitle: 'Untuk menentukan jam ramai, jadwal kasir, dan jam buka.',
        ),
        AppCard(
          child: ColumnChart(
            values: [for (final b in bundle.byHour) b.revenue],
            xLabels: [
              for (final b in bundle.byHour)
                b.bucket.toString().padLeft(2, '0'),
            ],
            color: c.accent,
            seriesLabel: 'Omzet',
            labelEvery: 3,
          ),
        ),
        _gap,
        const SectionTitle('Omzet per hari dalam seminggu'),
        AppCard(
          child: ColumnChart(
            values: [for (final b in bundle.byWeekday) b.revenue],
            xLabels: [for (final b in bundle.byWeekday) weekdayNames[b.bucket]],
            color: c.accent,
            seriesLabel: 'Omzet',
          ),
        ),
        _gap,
        const SectionTitle('Tabel harian'),
        DataTableCard(
          columns: const [
            TableColumnSpec('Tanggal', flex: 2),
            TableColumnSpec.number('Transaksi'),
            TableColumnSpec.number('Omzet', width: 140),
            TableColumnSpec.number('Laba kotor', width: 140),
          ],
          rows: [
            for (final d in days.reversed)
              TableRowData([
                CellText(Fmt.dateLong(d.date)),
                CellText(Fmt.number(d.transactions), number: true),
                CellText(Fmt.rupiah(d.revenue), number: true),
                CellText(Fmt.rupiah(d.grossProfit), number: true),
              ]),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 3. Produk
// -----------------------------------------------------------------------------

enum ProductSortBy { quantity, revenue, profit }

class ProductsSection extends StatefulWidget {
  const ProductsSection({super.key, required this.bundle});

  final ReportBundle bundle;

  @override
  State<ProductsSection> createState() => _ProductsSectionState();
}

class _ProductsSectionState extends State<ProductsSection> {
  ProductSortBy _sort = ProductSortBy.quantity;
  static const _limit = 100;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = [...widget.bundle.products]
      ..sort(
        (a, b) => switch (_sort) {
          ProductSortBy.quantity => b.quantity.compareTo(a.quantity),
          ProductSortBy.revenue => b.revenue.compareTo(a.revenue),
          ProductSortBy.profit => b.grossProfit.compareTo(a.grossProfit),
        },
      );
    final totalProfit = list.fold<int>(
      0,
      (s, p) => s + (p.grossProfit > 0 ? p.grossProfit : 0),
    );

    Widget abcCard(AbcClass k) {
      final items = list.where((p) => p.abc == k).toList();
      final profit = items.fold<int>(
        0,
        (s, p) => s + (p.grossProfit > 0 ? p.grossProfit : 0),
      );
      return StatCard(
        label: 'Kelas ${k.label}',
        value: '${items.length} barang',
        icon: CupertinoIcons.chart_bar_square_fill,
        color: c.chart2,
        caption: totalProfit == 0
            ? k.description
            : '${_pct(profit / totalProfit)} dari laba · ${k.description.split(' (').first}',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Analisis ABC (Pareto)',
          subtitle:
              'Fokuskan stok dan tempat di rak pada kelas A; kelas C kandidat '
              'promo, bundling, atau dikurangi.',
        ),
        StatGrid(cards: [for (final k in AbcClass.values) abcCard(k)]),
        _gap,
        Row(
          children: [
            const Expanded(child: SectionTitle('Kinerja per barang')),
            CupertinoSlidingSegmentedControl<ProductSortBy>(
              groupValue: _sort,
              padding: const EdgeInsets.all(2),
              onValueChanged: (v) => setState(() => _sort = v ?? _sort),
              children: const {
                ProductSortBy.quantity: _Seg('Terjual'),
                ProductSortBy.revenue: _Seg('Omzet'),
                ProductSortBy.profit: _Seg('Laba'),
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        DataTableCard(
          columns: const [
            TableColumnSpec('#', width: 36),
            TableColumnSpec('Barang', flex: 3),
            TableColumnSpec('ABC', width: 48),
            TableColumnSpec.number('Terjual', width: 90),
            TableColumnSpec.number('Omzet', width: 120),
            TableColumnSpec.number('Laba kotor', width: 120),
            TableColumnSpec.number('Margin', width: 80),
          ],
          rows: [
            for (final (i, p) in list.take(_limit).indexed)
              TableRowData([
                CellText('${i + 1}', muted: true),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CellText(p.name),
                    Text(
                      [p.code, if (p.category != null) p.category!].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                  ],
                ),
                _AbcBadge(p.abc),
                CellText(
                  '${Fmt.number(p.quantity)} ${p.unit ?? ''}'.trim(),
                  number: true,
                ),
                CellText(Fmt.rupiah(p.revenue), number: true),
                CellText(
                  Fmt.rupiah(p.grossProfit),
                  number: true,
                  color: p.grossProfit < 0 ? c.danger : null,
                ),
                CellText(_pct(p.margin), number: true, muted: true),
              ]),
          ],
          footer: [
            if (list.length > _limit)
              'Menampilkan $_limit dari ${list.length} barang; semua ada di '
                  'file export.',
            'Omzet dan laba per barang dari harga jual di faktur.',
          ].join(' '),
        ),
      ],
    );
  }
}

class _AbcBadge extends StatelessWidget {
  const _AbcBadge(this.abc);

  final AbcClass? abc;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (abc == null) return const SizedBox.shrink();
    final strong = abc == AbcClass.a;
    return Container(
      width: 24,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: strong ? c.chart2.withValues(alpha: 0.16) : c.fill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        abc!.label,
        style: AppTypography.caption.copyWith(
          color: c.label,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Text(label, style: AppTypography.footnote),
  );
}

// -----------------------------------------------------------------------------
// 4. Kategori
// -----------------------------------------------------------------------------

class CategoriesSection extends StatelessWidget {
  const CategoriesSection({super.key, required this.bundle});

  final ReportBundle bundle;

  @override
  Widget build(BuildContext context) {
    final cats = bundle.categories;
    final total = cats.fold<int>(0, (s, g) => s + g.revenue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Kontribusi per kategori',
          subtitle: 'Kategori mana yang perlu diperluas atau dikurangi.',
        ),
        DataTableCard(
          columns: const [
            TableColumnSpec('Kategori', flex: 2),
            TableColumnSpec('Kontribusi omzet', width: 180),
            TableColumnSpec.number('Terjual', width: 90),
            TableColumnSpec.number('Omzet', width: 130),
            TableColumnSpec.number('Laba kotor', width: 130),
            TableColumnSpec.number('Margin', width: 80),
          ],
          rows: [
            for (final g in cats)
              TableRowData([
                CellText(g.name),
                ShareMeter(ratio: total == 0 ? 0 : g.revenue / total),
                CellText(Fmt.number(g.quantity), number: true),
                CellText(Fmt.rupiah(g.revenue), number: true),
                CellText(Fmt.rupiah(g.grossProfit), number: true),
                CellText(_pct(g.margin), number: true, muted: true),
              ]),
          ],
          footer: 'Kategori mengikuti data barang saat ini.',
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 5. Stok
// -----------------------------------------------------------------------------

class StockSection extends StatelessWidget {
  const StockSection({
    super.key,
    required this.inventory,
    required this.stock,
    required this.now,
  });

  final InventorySummary inventory;
  final List<StockStatus> stock;
  final DateTime now;

  static const soonDays = 7;
  static const deadDays = 30;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final soon =
        stock
            .where((s) => s.daysOfCover != null && s.daysOfCover! <= soonDays)
            .toList()
          ..sort((a, b) => a.daysOfCover!.compareTo(b.daysOfCover!));
    final deadline = now.subtract(const Duration(days: deadDays));
    final dead =
        stock
            .where(
              (s) =>
                  s.stock > 0 &&
                  (s.lastSold == null || s.lastSold!.isBefore(deadline)),
            )
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final deadValue = dead.fold<int>(0, (s, x) => s + x.value);

    String days(double d) =>
        d < 1 ? '< 1 hari' : '${Fmt.number(d.round())} hari';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatGrid(
          cards: [
            StatCard(
              label: 'Nilai persediaan',
              value: Fmt.rupiah(inventory.costValue),
              icon: CupertinoIcons.cube_box_fill,
              color: c.accent,
              caption: 'Modal tertahan (stok × harga beli)',
            ),
            StatCard(
              label: 'Potensi omzet stok',
              value: Fmt.rupiah(inventory.retailValue),
              icon: CupertinoIcons.money_dollar_circle_fill,
              color: c.accent,
              caption: 'Stok × harga jual',
            ),
            StatCard(
              label: 'Akan habis ≤ $soonDays hari',
              value: '${soon.length} barang',
              icon: CupertinoIcons.exclamationmark_triangle_fill,
              color: soon.isEmpty ? c.labelTertiary : c.warning,
              caption: 'Berdasarkan rata-rata penjualan 30 hari',
            ),
            StatCard(
              label: 'Tidak laku $deadDays hari',
              value: '${dead.length} barang',
              icon: CupertinoIcons.moon_zzz_fill,
              color: dead.isEmpty ? c.labelTertiary : c.warning,
              caption: 'Modal tertahan ${Fmt.rupiah(deadValue)}',
            ),
          ],
        ),
        _gap,
        const SectionTitle(
          'Akan segera habis',
          subtitle: 'Perkiraan = stok ÷ rata-rata terjual per hari (30 hari).',
        ),
        DataTableCard(
          columns: const [
            TableColumnSpec('Barang', flex: 3),
            TableColumnSpec.number('Stok', width: 100),
            TableColumnSpec.number('Terjual/hari', width: 110),
            TableColumnSpec.number('Perkiraan habis', width: 140),
          ],
          emptyMessage:
              'Tidak ada barang yang diperkirakan habis dalam '
              '$soonDays hari.',
          rows: [
            for (final s in soon)
              TableRowData([
                CellText(s.name),
                CellText(
                  '${Fmt.number(s.stock)} ${s.unit ?? ''}'.trim(),
                  number: true,
                ),
                CellText(
                  Fmt.number((s.averageDailySales * 10).round() / 10),
                  number: true,
                ),
                CellText(days(s.daysOfCover!), number: true, bold: true),
              ]),
          ],
        ),
        _gap,
        const SectionTitle(
          'Barang tidak laku',
          subtitle:
              'Ada stok tapi tidak terjual $deadDays hari terakhir. Pertimbangkan '
              'diskon, bundling, atau berhenti menjual.',
        ),
        DataTableCard(
          columns: const [
            TableColumnSpec('Barang', flex: 3),
            TableColumnSpec.number('Stok', width: 100),
            TableColumnSpec.number('Modal tertahan', width: 140),
            TableColumnSpec.number('Terakhir terjual', width: 140),
          ],
          emptyMessage: 'Semua barang berstok terjual dalam $deadDays hari.',
          rows: [
            for (final s in dead.take(100))
              TableRowData([
                CellText(s.name),
                CellText(
                  '${Fmt.number(s.stock)} ${s.unit ?? ''}'.trim(),
                  number: true,
                ),
                CellText(Fmt.rupiah(s.value), number: true),
                CellText(
                  s.lastSold == null
                      ? 'Belum pernah'
                      : Fmt.dateShort(s.lastSold!),
                  number: true,
                  muted: true,
                ),
              ]),
          ],
          footer:
              'Bagian stok selalu memakai kondisi saat ini, tidak mengikuti '
              'rentang tanggal.',
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 6. Pembayaran
// -----------------------------------------------------------------------------

class PaymentsSection extends StatelessWidget {
  const PaymentsSection({super.key, required this.bundle});

  final ReportBundle bundle;

  @override
  Widget build(BuildContext context) {
    final total = bundle.payments.fold<int>(0, (s, g) => s + g.revenue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'Metode pembayaran',
          subtitle: 'Untuk mencocokkan uang masuk di laci, rekening, dan QRIS.',
        ),
        DataTableCard(
          columns: const [
            TableColumnSpec('Metode', flex: 2),
            TableColumnSpec('Porsi', width: 180),
            TableColumnSpec.number('Transaksi', width: 100),
            TableColumnSpec.number('Uang masuk', width: 140),
          ],
          rows: [
            for (final g in bundle.payments)
              TableRowData([
                CellText(g.name),
                ShareMeter(ratio: total == 0 ? 0 : g.revenue / total),
                CellText(Fmt.number(g.transactions), number: true),
                CellText(Fmt.rupiah(g.revenue), number: true),
              ]),
          ],
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 7. Kasir & terminal
// -----------------------------------------------------------------------------

class PeopleSection extends StatelessWidget {
  const PeopleSection({super.key, required this.bundle});

  final ReportBundle bundle;

  Widget _table(String label, List<GroupPerformance> list) => DataTableCard(
    columns: [
      TableColumnSpec(label, flex: 2),
      const TableColumnSpec.number('Transaksi', width: 100),
      const TableColumnSpec.number('Omzet', width: 140),
      const TableColumnSpec.number('Rata-rata belanja', width: 150),
      const TableColumnSpec.number('Laba kotor', width: 140),
    ],
    rows: [
      for (final g in list)
        TableRowData([
          CellText(g.name),
          CellText(Fmt.number(g.transactions), number: true),
          CellText(Fmt.rupiah(g.revenue), number: true),
          CellText(Fmt.rupiah(g.averageBasket), number: true),
          CellText(Fmt.rupiah(g.grossProfit), number: true),
        ]),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Per kasir'),
        _table('Kasir', bundle.cashiers),
        _gap,
        const SectionTitle(
          'Per terminal / lokasi',
          subtitle: 'Kode terminal diatur di Pengaturan › Terminal.',
        ),
        _table('Terminal', bundle.terminals),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// 8. Faktur
// -----------------------------------------------------------------------------

class InvoicesSection extends StatelessWidget {
  const InvoicesSection({super.key, required this.invoices});

  final List<SaleSummary> invoices;

  static const _limit = 500;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('d MMM HH:mm', 'id_ID');
    return DataTableCard(
      columns: const [
        TableColumnSpec('No. Faktur', flex: 2),
        TableColumnSpec('Waktu', width: 120),
        TableColumnSpec('Kasir', flex: 1),
        TableColumnSpec('Bayar', width: 130),
        TableColumnSpec.number('Total', width: 130),
      ],
      emptyMessage: 'Tidak ada transaksi pada periode ini.',
      rows: [
        for (final f in invoices.take(_limit))
          TableRowData([
            CellText(f.invoiceNo, bold: true),
            CellText(time.format(f.date), muted: true),
            CellText(f.cashierName, muted: true),
            CellText(f.paymentMethod, muted: true),
            CellText(Fmt.rupiah(f.total), number: true, bold: true),
          ], onTap: () => showSaleDetailSheet(context, f)),
      ],
      footer: invoices.length > _limit
          ? 'Menampilkan $_limit dari ${Fmt.number(invoices.length)} faktur '
                'terbaru; semua ada di file export.'
          : 'Ketuk faktur untuk melihat rinciannya.',
    );
  }
}
