import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/save_file.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/state_views.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/domain/sale.dart';
import '../../stores/presentation/store_scope.dart';
import '../data/report_export.dart';
import '../data/report_repository.dart';
import '../domain/report_models.dart';
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
  payments('Pembayaran', CupertinoIcons.creditcard),
  people('Kasir & Terminal', CupertinoIcons.person_2),
  invoices('Faktur', CupertinoIcons.doc_text);

  const ReportSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Laporan keuangan & penjualan (admin). Satu filter tanggal di atas berlaku
/// untuk semua bagian, sehingga angka di setiap bagian dan file export sama.
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
      );
      String day(DateTime d) =>
          '${d.year}${d.month.toString().padLeft(2, '0')}'
          '${d.day.toString().padLeft(2, '0')}';
      final path = await saveFileAs(
        fileName: 'laporan-${day(_range.start)}-${day(_range.lastDay)}.xlsx',
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
          _Chips<RangePreset>(
            values: RangePreset.values,
            selected: _preset,
            label: (p) => p == RangePreset.custom && _preset == p
                ? _range.label
                : p.label,
            icon: (p) =>
                p == RangePreset.custom ? CupertinoIcons.calendar : null,
            onSelected: _choosePreset,
          ),
          const SizedBox(height: AppSpacing.sm),
          _Chips<ReportSection>(
            values: ReportSection.values,
            selected: _section,
            label: (s) => s.label,
            icon: (s) => s.icon,
            onSelected: (s) => setState(() => _section = s),
            subtle: true,
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
                  child: _buildSection(bundle),
                ),
        ),
      ],
    );
  }

  Widget _buildSection(ReportBundle bundle) {
    switch (_section) {
      case ReportSection.summary:
        return SummarySection(bundle: bundle);
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

/// Deretan pilihan berbentuk kapsul (satu terpilih), bisa melipat ke baris
/// berikutnya di layar sempit.
class _Chips<T> extends StatelessWidget {
  const _Chips({
    required this.values,
    required this.selected,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.subtle = false,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final IconData? Function(T) icon;
  final ValueChanged<T> onSelected;

  /// Gaya lebih tenang untuk navigasi bagian (bukan filter).
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final v in values)
          PressableScale(
            onPressed: () => onSelected(v),
            pressedScale: 0.95,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: AppDurations.fast,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: v == selected
                    ? (subtle ? c.accentTint : c.accent)
                    : c.fill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon(v) != null) ...[
                    Icon(
                      icon(v),
                      size: 15,
                      color: v == selected
                          ? (subtle ? c.accent : CupertinoColors.white)
                          : c.labelSecondary,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label(v),
                    style: AppTypography.footnote.copyWith(
                      color: v == selected
                          ? (subtle ? c.accent : CupertinoColors.white)
                          : c.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
