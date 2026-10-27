import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/save_file.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/choice_chips.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/section_tabs.dart';
import '../../../core/widgets/state_views.dart';
import '../../audit/presentation/activity_section.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale.dart';
import '../../stores/domain/store.dart';
import '../../stores/presentation/store_scope.dart';
import '../../stores/presentation/store_scope_chips.dart';
import '../data/report_export.dart';
import '../data/report_repository.dart';
import '../domain/report_models.dart';
import 'promo_section.dart';
import 'report_sections.dart';

final reportBundleProvider = FutureProvider.autoDispose
    .family<ReportBundle, ReportRange>(
      (ref, range) => ref.watch(reportRepositoryProvider).bundle(range),
    );

final _stockProvider =
    FutureProvider.autoDispose<(InventorySummary, List<StockStatus>)>((
      ref,
    ) async {
      final repo = ref.watch(reportRepositoryProvider);
      return (await repo.inventory(), await repo.stockStatus());
    });

final _invoicesProvider = StreamProvider.autoDispose
    .family<List<SaleSummary>, ReportRange>(
      (ref, range) => ref
          .watch(salesRepositoryProvider)
          .watchBetween(
            range.start,
            range.end,
            storeId: ref.watch(storeScopeProvider),
          ),
    );

enum ReportSection {
  summary('Ringkasan', CupertinoIcons.square_grid_2x2),
  trend('Tren', CupertinoIcons.graph_square),
  products('Produk', CupertinoIcons.cube_box),
  categories('Kategori', CupertinoIcons.square_stack_3d_up),
  stock('Stok', CupertinoIcons.archivebox),
  payments('Pembayaran & Voucher', CupertinoIcons.creditcard),
  people('Kasir & Terminal', CupertinoIcons.person_2),
  invoices('Faktur', CupertinoIcons.doc_text),
  promo('Saran Promo', CupertinoIcons.lightbulb),
  activity('Aktivitas', CupertinoIcons.shield_lefthalf_fill);

  const ReportSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Laporan keuangan & penjualan (admin). Satu filter tanggal (dan toko, bila
/// > 1 toko aktif) di atas berlaku untuk semua bagian, sehingga angka di
/// setiap bagian dan file export sama.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  RangePreset _preset = RangePreset.last7;
  late ReportRange _range = ReportRange.preset(_preset, DateTime.now());
  ReportSection _section = ReportSection.summary;

  /// Data terakhir yang berhasil dimuat; tetap tampil (samar) saat rentang
  /// baru sedang dimuat, tanpa kedip.
  ReportBundle? _last;
  bool _exporting = false;

  Future<void> _choosePreset(RangePreset preset) async {
    if (preset != RangePreset.custom) {
      setState(() {
        _preset = preset;
        _range = ReportRange.preset(preset, DateTime.now());
      });
      return;
    }
    final from = await AppDialogs.pickDate(
      context,
      title: 'Dari tanggal',
      initial: _range.start,
    );
    if (from == null || !mounted) return;
    final to = await AppDialogs.pickDate(
      context,
      title: 'Sampai tanggal',
      initial: _range.lastDay.isBefore(from) ? from : _range.lastDay,
    );
    if (to == null) return;
    setState(() {
      _preset = RangePreset.custom;
      _range = ReportRange.days(from, to);
    });
  }

  void _refresh() {
    ref.invalidate(reportBundleProvider(_range));
    ref.invalidate(_stockProvider);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final store = ref.read(activeStoreProvider);
    try {
      final repo = ref.read(reportRepositoryProvider);
      final bundle = await ref.read(reportBundleProvider(_range).future);
      final invoices = await ref
          .read(salesRepositoryProvider)
          .watchBetween(
            _range.start,
            _range.end,
            storeId: ref.read(storeScopeProvider),
          )
          .first;
      final bytes = exportReportXlsx(
        bundle: bundle,
        inventory: await repo.inventory(),
        stock: await repo.stockStatus(),
        invoices: invoices,
        storeName: store?.name ?? 'Semua toko',
      );
      String day(DateTime d) =>
          '${d.year}${d.month.toString().padLeft(2, '0')}'
          '${d.day.toString().padLeft(2, '0')}';
      final path = await saveFileAs(
        fileName:
            'laporan-${store == null ? '' : '${_slug(store.name)}-'}'
            '${day(_range.start)}-${day(_range.lastDay)}.xlsx',
        bytes: bytes,
        extension: 'xlsx',
        mimeType: xlsxMime,
      );
      if (path != null && mounted) {
        await AppDialogs.alert(
          context,
          title: 'Laporan tersimpan',
          message: '$path\n\nSetiap bagian ada di sheet tersendiri.',
        );
      }
    } on Object catch (e) {
      if (mounted) {
        await AppDialogs.alert(context, title: 'Gagal export', message: '$e');
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reportBundleProvider(_range));
    if (async.hasValue) _last = async.value;
    final bundle = _last;
    final reloading = async.isLoading && bundle != null;
    final stores = activeStores(ref);
    final isAdmin = ref.watch(authControllerProvider)?.isAdmin ?? false;
    // Filter & rincian per toko hanya berarti bila ada > 1 toko aktif, dan
    // hanya admin yang bisa berpindah toko (peran lain: laporan tokonya).
    final multiStore = stores.length > 1 && isAdmin;
    // Catatan aktivitas (pengawasan karyawan) khusus admin.
    final sections = [
      for (final s in ReportSection.values)
        if (isAdmin || s != ReportSection.activity) s,
    ];
    if (!sections.contains(_section)) _section = ReportSection.summary;

    return LargeTitlePage(
      title: 'Laporan',
      subtitle:
          '${_range.label} · '
          '${ref.watch(activeStoreProvider)?.name ?? 'Semua toko'}',
      actions: [
        AppIconButton(
          icon: CupertinoIcons.arrow_clockwise,
          tooltip: 'Muat ulang',
          filled: true,
          onPressed: _refresh,
        ),
        AppButton(
          label: 'Export Excel',
          icon: CupertinoIcons.square_arrow_up,
          variant: AppButtonVariant.gray,
          loading: _exporting,
          onPressed: _export,
        ),
      ],
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Satu baris filter: toko (tombol pilih) + rentang tanggal.
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (multiStore) const _StoreButton(),
              ChoiceChips<RangePreset>(
                values: RangePreset.values,
                selected: _preset,
                label: (p) => p == RangePreset.custom && _preset == p
                    ? _range.label
                    : p.label,
                icon: (p) =>
                    p == RangePreset.custom ? CupertinoIcons.calendar : null,
                onSelected: _choosePreset,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SectionTabs<ReportSection>(
            values: sections,
            selected: _section,
            label: (s) => s.label,
            onSelected: (s) => setState(() => _section = s),
          ),
        ],
      ),
      slivers: [
        SliverToBoxAdapter(
          child: async.hasError && bundle == null
              ? ErrorBanner(message: 'Gagal memuat laporan: ${async.error}')
              : bundle == null
              ? const SizedBox(height: 320, child: LoadingState())
              : AnimatedOpacity(
                  duration: AppDurations.fast,
                  opacity: reloading ? 0.5 : 1,
                  child: _buildSection(bundle, multiStore ? stores : null),
                ),
        ),
      ],
    );
  }

  Widget _buildSection(ReportBundle bundle, List<Store>? stores) {
    switch (_section) {
      case ReportSection.summary:
        if (stores == null || ref.watch(storeScopeProvider) != null) {
          return SummarySection(bundle: bundle);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PerStore(bundle: bundle, stores: stores),
            const SizedBox(height: AppSpacing.xl),
            SummarySection(bundle: bundle),
          ],
        );
      case ReportSection.trend:
        return TrendSection(bundle: bundle);
      case ReportSection.products:
        return ProductsSection(bundle: bundle);
      case ReportSection.categories:
        return CategoriesSection(bundle: bundle);
      case ReportSection.stock:
        final stock = ref.watch(_stockProvider);
        return stock.when(
          loading: () => const SizedBox(height: 320, child: LoadingState()),
          error: (e, _) => ErrorBanner(message: '$e'),
          data: (d) =>
              StockSection(inventory: d.$1, stock: d.$2, now: DateTime.now()),
        );
      case ReportSection.payments:
        return PaymentsSection(bundle: bundle);
      case ReportSection.people:
        return PeopleSection(bundle: bundle);
      case ReportSection.activity:
        return ActivitySection(
          range: _range,
          storeId: ref.watch(storeScopeProvider),
        );
      case ReportSection.promo:
        return const PromoSection();
      case ReportSection.invoices:
        final invoices = ref.watch(_invoicesProvider(_range));
        return invoices.when(
          loading: () => const SizedBox(height: 320, child: LoadingState()),
          error: (e, _) => ErrorBanner(message: '$e'),
          data: (list) => InvoicesSection(invoices: list),
        );
    }
  }
}

/// Nama toko untuk nama file: huruf kecil, selain huruf/angka jadi "-".
String _slug(String name) => name
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

/// Omzet tiap toko pada rentang laporan (saat melihat semua toko), termasuk
/// toko tanpa penjualan. Ketuk = laporan toko itu saja.
class _PerStore extends ConsumerWidget {
  const _PerStore({required this.bundle, required this.stores});

  final ReportBundle bundle;
  final List<Store> stores;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final byName = {for (final g in bundle.stores) g.name: g};
    final total = bundle.summary.revenue;
    final rows = [
      for (final st in stores)
        (st.id, byName[st.name] ?? GroupPerformance(name: st.name)),
    ]..sort((a, b) => b.$2.revenue.compareTo(a.$2.revenue));

    return InsetGroupedSection(
      header: 'Per toko',
      footer: 'Ketuk toko untuk melihat laporan toko itu saja.',
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
                      'laba ${Fmt.rupiah(g.grossProfit)}'
                      '${total > 0 ? ' · ${Fmt.percent(g.revenue / total)} omzet' : ''}',
            value: Fmt.rupiah(g.revenue),
            onPressed: () => ref.read(storeScopeProvider.notifier).select(id),
          ),
      ],
    );
  }
}

/// Tombol toko yang dipakai laporan ("Semua toko" / nama toko) → popup
/// pilih toko; menulis ke [storeScopeProvider] seperti pemilih di sidebar.
class _StoreButton extends ConsumerWidget {
  const _StoreButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final store = ref.watch(activeStoreProvider);
    return PressableScale(
      onPressed: () => pickStoreScope(context, ref),
      pressedScale: 0.95,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: c.accentTint,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              store == null
                  ? CupertinoIcons.square_grid_2x2
                  : CupertinoIcons.house_fill,
              size: 15,
              color: c.accent,
            ),
            const SizedBox(width: 6),
            Text(
              store?.name ?? 'Semua toko',
              style: AppTypography.footnote.copyWith(
                color: c.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_down, size: 12, color: c.accent),
          ],
        ),
      ),
    );
  }
}
