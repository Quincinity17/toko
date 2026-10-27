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
import '../../auth/presentation/auth_controller.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product.dart';
import '../../reports/data/report_repository.dart';
import '../../reports/domain/report_models.dart';
import '../../stores/domain/store.dart';
import '../../stores/presentation/store_scope.dart';
import '../../stores/presentation/store_scope_chips.dart';
import '../../stock/data/stock_repository.dart';
import '../../stock/domain/stock_alert.dart';

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

final _storeSalesProvider = StreamProvider.autoDispose
    .family<List<GroupPerformance>, ReportRange>(
      (ref, range) =>
          ref.watch(reportRepositoryProvider).watchStoreSales(range),
    );

/// Stok menipis di toko yang dipilih (atau stok gabungan semua toko).
ProductFilter _lowStockFilter(Ref ref) => ProductFilter(
  lowStockOnly: true,
  sort: ProductSort.stockLow,
  storeId: ref.watch(storeScopeProvider),
);

final _lowStockProvider = StreamProvider.autoDispose<List<Product>>(
  (ref) => ref
      .watch(productRepositoryProvider)
      .watchPage(_lowStockFilter(ref), page: 0, pageSize: 5),
);

final _lowStockCountProvider = StreamProvider.autoDispose<int>(
  (ref) =>
      ref.watch(productRepositoryProvider).watchCount(_lowStockFilter(ref)),
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
    final scope = ref.watch(storeScopeProvider);
    // Satu toko: kartu & daftar memakai peringatan stok (minus, menipis,
    // perlu dicek); semua toko: stok menipis gabungan.
    final alerts = ref.watch(stockAlertsProvider(scope)).value;
    final alertProducts = {for (final a in alerts ?? const []) a.row.productId};
    final dangerCount = {
      for (final a in alerts ?? const <StockAlert>[])
        if (a.kind.level == StockAlertLevel.danger) a.row.productId,
    }.length;
    final checkCount = {
      for (final a in alerts ?? const <StockAlert>[])
        if (a.kind.level == StockAlertLevel.check) a.row.productId,
    }.length;
    final openStock = switch (ref.watch(authControllerProvider)) {
      final u? when u.canAccess(AppRoutes.stok) => () => context.go(
        '${AppRoutes.stok}?view=peringatan',
      ),
      _ => null,
    };
    final stores = activeStores(ref);
    final user = ref.watch(authControllerProvider);
    // Filter & ringkasan per toko hanya berarti bila ada > 1 toko aktif, dan
    // hanya admin yang bisa berpindah toko (peran lain: tokonya sendiri).
    final multiStore = stores.length > 1 && (user?.isAdmin ?? false);

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
            : s!.hasMissingCost
            ? 'Margin ${Fmt.percent(s.margin!)} · ada barang tanpa harga beli'
            : 'Margin ${Fmt.percent(s.margin!)}',
      ),
      StatCard(
        label: 'Transaksi',
        value: Fmt.number(s?.transactions ?? 0),
        icon: CupertinoIcons.doc_text_fill,
        color: c.accent,
        caption: 'Rata-rata belanja ${Fmt.rupiah(s?.averageBasket ?? 0)}',
      ),
      if (alerts != null)
        StatCard(
          label: 'Peringatan stok',
          value: Fmt.number(alertProducts.length),
          icon: CupertinoIcons.exclamationmark_triangle_fill,
          color: dangerCount > 0
              ? c.danger
              : alertProducts.isNotEmpty
              ? c.warning
              : c.labelTertiary,
          caption: alertProducts.isEmpty
              ? 'Semua stok aman'
              : [
                  if (dangerCount > 0) '$dangerCount minus/habis',
                  if (checkCount > 0) '$checkCount perlu dicek',
                  if (dangerCount == 0 && checkCount == 0) 'Perlu dibeli',
                ].join(' · '),
          onPressed: openStock,
        )
      else
        StatCard(
          label: 'Stok menipis',
          value: Fmt.number(lowCount),
          icon: CupertinoIcons.exclamationmark_triangle_fill,
          color: lowCount > 0 ? c.warning : c.labelTertiary,
          caption: lowCount > 0 ? 'Perlu dibeli ulang' : 'Semua stok aman',
          onPressed: switch (user) {
            final u? when u.canAccess(AppRoutes.produk) => () => context.go(
              AppRoutes.produk,
            ),
            final u? when u.canAccess(AppRoutes.stok) => () => context.go(
              AppRoutes.stok,
            ),
            _ => null,
          },
        ),
    ];

    return LargeTitlePage(
      title: 'Dashboard',
      subtitle:
          '${Fmt.dateLong(now)} · '
          '${ref.watch(activeStoreProvider)?.name ?? 'Semua toko'}',
      actions: [
        if (user?.canAccess(AppRoutes.laporan) ?? false)
          AppButton(
            label: 'Lihat Laporan',
            icon: CupertinoIcons.chart_bar_alt_fill,
            variant: AppButtonVariant.gray,
            onPressed: () => context.go(AppRoutes.laporan),
          ),
      ],
      bottom: multiStore ? StoreScopeChips(stores: stores) : null,
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
        if (multiStore && scope == null) ...[
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
          SliverToBoxAdapter(
            child: _PerStore(range: today, stores: stores),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(child: _WeekChart(range: week)),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final top = _TopToday(range: today);
              final low = alerts == null
                  ? const _LowStock()
                  : _Alerts(alerts: alerts, onOpen: openStock);
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
                  Expanded(child: low),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Omzet hari ini tiap toko (saat melihat semua toko). Ketuk = buka
/// dashboard toko itu.
class _PerStore extends ConsumerWidget {
  const _PerStore({required this.range, required this.stores});

  final ReportRange range;
  final List<Store> stores;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sales = ref.watch(_storeSalesProvider(range)).value ?? const [];
    final byName = {for (final g in sales) g.name: g};
    final rows = [
      for (final st in stores)
        (st.id, byName[st.name] ?? GroupPerformance(name: st.name)),
    ]..sort((a, b) => b.$2.revenue.compareTo(a.$2.revenue));

    return InsetGroupedSection(
      header: 'Per toko hari ini',
      footer: 'Ketuk toko untuk melihat dashboard toko itu.',
      children: [
        for (final (id, g) in rows)
          InsetGroupedTile(
            leading: Icon(
              CupertinoIcons.house_fill,
              size: 18,
              color: g.revenue > 0 ? c.accent : c.labelTertiary,
            ),
            title: g.name,
            subtitle: g.transactions == 0
                ? 'Belum ada transaksi'
                : '${Fmt.number(g.transactions)} transaksi · '
                      'laba ${Fmt.rupiah(g.grossProfit)}',
            value: Fmt.rupiah(g.revenue),
            onPressed: () => ref.read(storeScopeProvider.notifier).select(id),
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

/// Peringatan stok teratas toko yang dipilih (lihat halaman Stok).
class _Alerts extends StatelessWidget {
  const _Alerts({required this.alerts, required this.onOpen});

  final List<StockAlert> alerts;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = alerts.take(5).toList();
    return InsetGroupedSection(
      header: 'Peringatan stok',
      footer: alerts.isEmpty
          ? 'Tidak ada stok minus, menipis, atau yang perlu dicek.'
          : alerts.length > top.length
          ? '${alerts.length - top.length} peringatan lain di halaman Stok.'
          : 'Ketuk untuk membuka halaman Stok.',
      children: [
        for (final a in top)
          InsetGroupedTile(
            leading: Icon(
              a.kind.level == StockAlertLevel.check
                  ? CupertinoIcons.question_circle_fill
                  : CupertinoIcons.exclamationmark_triangle_fill,
              size: 18,
              color: switch (a.kind.level) {
                StockAlertLevel.danger => c.danger,
                StockAlertLevel.warning => c.warning,
                StockAlertLevel.check => c.labelSecondary,
              },
            ),
            title: a.row.name,
            subtitle: [
              ?a.row.storeName,
              a.kind.label,
              if (a.suggestedBuy case final buy?) 'beli ±${Fmt.number(buy)}',
            ].join(' · '),
            value: '${Fmt.number(a.row.stock)} ${a.row.unit ?? ''}'.trim(),
            onPressed: onOpen,
          ),
        if (alerts.isEmpty) const InsetGroupedTile(title: '–'),
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
    final user = ref.watch(authControllerProvider);
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
            onPressed: switch (user) {
              final u? when u.canAccess(AppRoutes.produk) => () => context.go(
                AppRoutes.produk,
              ),
              final u? when u.canAccess(AppRoutes.stok) => () => context.go(
                AppRoutes.stok,
              ),
              _ => null,
            },
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
