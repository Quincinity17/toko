import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/charts.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product.dart';
import '../../reports/data/report_repository.dart';
import '../../reports/domain/report_models.dart';

// Provider di-key dengan rentang tanggal, jadi otomatis berganti hari saat
// halaman dibangun ulang setelah tengah malam.

final _summaryProvider = StreamProvider.autoDispose
    .family<SalesSummary, ReportRange>(
      (ref, range) => ref.watch(reportRepositoryProvider).watchSummary(range),
    );

final _dailyProvider = StreamProvider.autoDispose
    .family<List<DailyPoint>, ReportRange>(
      (ref, range) => ref.watch(reportRepositoryProvider).watchDaily(range),
    );

final _topProvider = StreamProvider.autoDispose
    .family<List<ProductPerformance>, ReportRange>(
      (ref, range) =>
          ref.watch(reportRepositoryProvider).watchTopProducts(range),
    );

const _lowStockFilter = ProductFilter(
  lowStockOnly: true,
  sort: ProductSort.stockLow,
);

final _lowStockProvider = StreamProvider.autoDispose<List<Product>>(
  (ref) => ref
      .watch(productRepositoryProvider)
      .watchPage(_lowStockFilter, page: 0, pageSize: 5),
);

final _lowStockCountProvider = StreamProvider.autoDispose<int>(
  (ref) => ref.watch(productRepositoryProvider).watchCount(_lowStockFilter),
);

/// Ringkasan hari ini untuk admin, diperbarui otomatis setiap ada transaksi.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final now = DateTime.now();
    final today = ReportRange.preset(RangePreset.today, now);
    final week = ReportRange.preset(RangePreset.last7, now);

    final s = ref.watch(_summaryProvider(today)).value;
    final prev = ref.watch(_summaryProvider(today.previous)).value;
    final lowCount = ref.watch(_lowStockCountProvider).value ?? 0;

    final cards = [
      StatCard(
        label: 'Omzet hari ini',
        value: Fmt.rupiah(s?.revenue ?? 0),
        icon: CupertinoIcons.money_dollar_circle_fill,
        color: c.accent,
        delta: s == null || prev == null
            ? null
            : growth(s.revenue, prev.revenue),
        deltaLabel: 'vs kemarin (${Fmt.rupiah(prev?.revenue ?? 0)})',
        caption: 'Kemarin ${Fmt.rupiah(prev?.revenue ?? 0)}',
      ),
      StatCard(
        label: 'Laba kotor',
        value: Fmt.rupiah(s?.grossProfit ?? 0),
        icon: CupertinoIcons.chart_pie_fill,
        color: c.chart2,
        caption: s?.margin == null
            ? 'Belum ada penjualan'
            : 'Margin ${Fmt.percent(s!.margin!)}',
      ),
      StatCard(
        label: 'Transaksi',
        value: Fmt.number(s?.transactions ?? 0),
        icon: CupertinoIcons.doc_text_fill,
        color: c.accent,
        caption: 'Rata-rata belanja ${Fmt.rupiah(s?.averageBasket ?? 0)}',
      ),
      StatCard(
        label: 'Stok menipis',
        value: Fmt.number(lowCount),
        icon: CupertinoIcons.exclamationmark_triangle_fill,
        color: lowCount > 0 ? c.warning : c.labelTertiary,
        caption: lowCount > 0 ? 'Perlu dibeli ulang' : 'Semua stok aman',
        onPressed: () => context.go(AppRoutes.produk),
      ),
    ];

    return LargeTitlePage(
      title: 'Dashboard',
      subtitle: Fmt.dateLong(now),
      actions: [
        AppButton(
          label: 'Lihat Laporan',
          icon: CupertinoIcons.chart_bar_alt_fill,
          variant: AppButtonVariant.gray,
          onPressed: () => context.go(AppRoutes.laporan),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1000
                  ? 4
                  : constraints.maxWidth > 560
                  ? 2
                  : 1;
              const gap = AppSpacing.md;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final card in cards) SizedBox(width: width, child: card),
                ],
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(child: _WeekChart(range: week)),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final top = _TopToday(range: today);
              const low = _LowStock();
              if (constraints.maxWidth < 820) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    top,
                    const SizedBox(height: AppSpacing.xl),
                    low,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: top),
                  const SizedBox(width: AppSpacing.xl),
                  const Expanded(child: low),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekChart extends ConsumerWidget {
  const _WeekChart({required this.range});

  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final days = ref.watch(_dailyProvider(range)).value;
    final total = days?.fold<int>(0, (s, d) => s + d.revenue) ?? 0;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Omzet 7 hari terakhir',
            style: AppTypography.headline.copyWith(color: c.label),
          ),
          Text(
            'Total ${Fmt.rupiah(total)}',
            style: AppTypography.subheadline.copyWith(color: c.labelSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (days == null)
            const SizedBox(height: 240, child: LoadingState())
          else if (total == 0)
            // Tinggi minimal, bukan tetap: teks boleh membungkus tanpa meluap.
            Container(
              constraints: const BoxConstraints(minHeight: 240),
              alignment: Alignment.center,
              child: const EmptyState(
                icon: CupertinoIcons.chart_bar_alt_fill,
                title: 'Belum ada penjualan',
                message: 'Grafik muncul setelah ada transaksi di 7 hari ini.',
              ),
            )
          else
            TrendLineChart(
              series: [
                ChartSeries(
                  label: 'Omzet',
                  color: c.accent,
                  values: [for (final d in days) d.revenue],
                ),
              ],
              xLabels: [for (final d in days) Fmt.dayShort(d.date)],
            ),
        ],
      ),
    );
  }
}

class _TopToday extends ConsumerWidget {
  const _TopToday({required this.range});

  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(_topProvider(range)).value ?? const [];
    return InsetGroupedSection(
      header: 'Terlaris hari ini',
      footer: top.isEmpty
          ? 'Belum ada barang terjual hari ini.'
          : 'Urut dari jumlah terjual.',
      children: [
        for (final (i, p) in top.indexed)
          InsetGroupedTile(
            leading: _Rank(i + 1),
            title: p.name,
            subtitle: '${Fmt.number(p.quantity)} ${p.unit ?? ''} terjual'
                .trim(),
            value: Fmt.rupiah(p.revenue),
          ),
        if (top.isEmpty) const InsetGroupedTile(title: '–'),
      ],
    );
  }
}

class _LowStock extends ConsumerWidget {
  const _LowStock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final list = ref.watch(_lowStockProvider).value ?? const [];
    return InsetGroupedSection(
      header: 'Stok menipis',
      footer: list.isEmpty
          ? 'Tidak ada barang di bawah stok minimum.'
          : 'Stok ≤ stok minimum, urut dari yang paling sedikit.',
      children: [
        for (final p in list)
          InsetGroupedTile(
            leading: Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              size: 18,
              color: c.warning,
            ),
            title: p.name,
            subtitle: 'Minimum ${Fmt.number(p.minStock)}',
            value: '${Fmt.number(p.stock)} ${p.unitName ?? ''}'.trim(),
            onPressed: () => context.go(AppRoutes.produk),
          ),
        if (list.isEmpty) const InsetGroupedTile(title: '–'),
      ],
    );
  }
}

class _Rank extends StatelessWidget {
  const _Rank(this.rank);

  final int rank;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.fill, shape: BoxShape.circle),
      child: Text(
        '$rank',
        style: AppTypography.footnote.copyWith(
          color: c.label,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
