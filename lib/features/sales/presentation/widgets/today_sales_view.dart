import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../stores/presentation/store_scope.dart';
import '../../data/sales_repository.dart';
import '../../domain/day_total.dart';
import '../../domain/sale.dart';
import 'sale_detail_sheet.dart';

/// Transaksi hari ini di toko yang dipakai, diperbarui otomatis setiap ada
/// penjualan baru.
final todaySalesProvider = StreamProvider.autoDispose<List<SaleSummary>>(
  (ref) => ref
      .watch(salesRepositoryProvider)
      .watchDay(DateTime.now(), storeId: ref.watch(storeScopeProvider)),
);

const _cols = <(String, double?, TextAlign)>[
  ('No. Faktur', 190, TextAlign.left),
  ('Jam', 70, TextAlign.left),
  ('Kasir', null, TextAlign.left),
  ('Barang', 70, TextAlign.right),
  ('Bayar', 150, TextAlign.left),
  ('Total', 130, TextAlign.right),
  ('', 32, TextAlign.right),
];

/// Faktur semua tanggal di toko yang dipakai yang nomornya memuat kata
/// pencarian (kasir mencari faktur lama dari nomor di struk).
final _invoiceSearchProvider = FutureProvider.autoDispose
    .family<List<SaleSummary>, String>(
      (ref, query) => ref
          .watch(salesRepositoryProvider)
          .search(query, storeId: ref.watch(storeScopeProvider)),
    );

/// Tab "Hari Ini": daftar faktur hari ini + total di bawah (untuk menutup
/// kasir), dan pencarian faktur lama (semua tanggal) dari nomornya, mis.
/// untuk retur/tukar barang.
class TodaySalesView extends ConsumerStatefulWidget {
  const TodaySalesView({super.key});

  @override
  ConsumerState<TodaySalesView> createState() => _TodaySalesViewState();
}

class _TodaySalesViewState extends ConsumerState<TodaySalesView> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => setState(() => _query = text.trim()),
    );
  }

  /// Enter: satu hasil (atau nomor persis) langsung dibuka rinciannya.
  Future<void> _onSubmitted(String text) async {
    _debounce?.cancel();
    final q = text.trim();
    setState(() => _query = q);
    if (q.isEmpty) return;
    final found = await ref.read(_invoiceSearchProvider(q).future);
    if (!mounted) return;
    final exact = found.where(
      (f) => f.invoiceNo.toUpperCase() == q.toUpperCase(),
    );
    final pick = exact.isNotEmpty
        ? exact.first
        : found.length == 1
        ? found.single
        : null;
    if (pick != null) await showSaleDetailSheet(context, pick);
  }

  @override
  Widget build(BuildContext context) {
    final compact = AppBreakpoints.isCompact(context);
    final searching = _query.isNotEmpty;
    final sales = searching
        ? ref.watch(_invoiceSearchProvider(_query))
        : ref.watch(todaySalesProvider);
    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(
              AppSpacing.pageGutterCompact,
              0,
              AppSpacing.pageGutterCompact,
              AppSpacing.sm,
            )
          : const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AppTextField(
                controller: _search,
                placeholder: 'Cari no. faktur (semua tanggal)',
                prefixIcon: CupertinoIcons.search,
                onChanged: _onChanged,
                onSubmitted: _onSubmitted,
              ),
            ),
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          Expanded(
            child: sales.when(
              skipLoadingOnReload: true,
              loading: () => const LoadingState(),
              error: (e, _) =>
                  ErrorBanner(message: 'Gagal memuat transaksi: $e'),
              data: (list) => _SalesTable(sales: list, searching: searching),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesTable extends StatelessWidget {
  const _SalesTable({required this.sales, this.searching = false});

  final List<SaleSummary> sales;

  /// Hasil pencarian (semua tanggal): tanggal ikut tampil, tanpa total.
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final header = AppTypography.caption.copyWith(
      color: c.labelSecondary,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );
    // HP: daftar ringkas tanpa baris judul kolom.
    final compact = AppBreakpoints.isCompact(context);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          if (!compact) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  for (final (label, width, align) in _cols)
                    _cell(
                      width,
                      Text(
                        label.toUpperCase(),
                        textAlign: align,
                        style: header,
                      ),
                    ),
                ],
              ),
            ),
            Container(height: 0.5, color: c.separator),
          ],
          Expanded(
            child: sales.isEmpty
                ? searching
                      ? const EmptyState(
                          icon: CupertinoIcons.search,
                          title: 'Faktur tidak ditemukan',
                          message:
                              'Ketik sebagian nomor faktur dari struk, '
                              'mis. 20261001-0003.',
                        )
                      : const EmptyState(
                          icon: CupertinoIcons.doc_text,
                          title: 'Belum ada transaksi hari ini',
                          message:
                              'Transaksi yang selesai di tab Transaksi Baru '
                              'akan muncul di sini.',
                        )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: sales.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Container(height: 0.5, color: c.separator),
                    ),
                    itemBuilder: (context, i) => compact
                        ? _CompactSaleRow(sale: sales[i], showDate: searching)
                        : _SaleRow(sale: sales[i], showDate: searching),
                  ),
          ),
          if (sales.isNotEmpty && !searching) ...[
            Container(height: 0.5, color: c.separator),
            _TotalFooter(total: DayTotal.of(sales), compact: compact),
          ],
        ],
      ),
    );
  }
}

/// Total hari ini di bawah tabel: total bersih, jumlah transaksi, dan
/// rincian per metode bayar (Tunai = uang yang seharusnya ada di laci).
class _TotalFooter extends StatelessWidget {
  const _TotalFooter({required this.total, required this.compact});

  final DayTotal total;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final numbers = const [FontFeature.tabularFigures()];
    final methodStyle = AppTypography.subheadline.copyWith(
      color: c.labelSecondary,
      fontFeatures: numbers,
    );
    final methods = [
      for (final MapEntry(key: name, value: amount) in total.byMethod.entries)
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$name  '),
              TextSpan(
                text: Fmt.rupiah(amount),
                style: TextStyle(color: c.label, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          style: methodStyle,
        ),
    ];
    final sum = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'TOTAL HARI INI · ${Fmt.number(total.transactions)} TRANSAKSI',
          style: AppTypography.caption.copyWith(
            color: c.labelSecondary,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        Text(
          Fmt.rupiah(total.total),
          style: AppTypography.title2.copyWith(
            color: c.label,
            fontWeight: FontWeight.w700,
            fontFeatures: numbers,
          ),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(spacing: AppSpacing.lg, runSpacing: 4, children: methods),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(fit: BoxFit.scaleDown, child: sum),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: AppSpacing.xl,
                    runSpacing: 4,
                    children: methods,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                sum,
              ],
            ),
    );
  }
}

Widget _cell(double? width, Widget child) => width == null
    ? Expanded(child: child)
    : SizedBox(width: width, child: child);

class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.sale, this.showDate = false});

  final SaleSummary sale;

  /// Hasil pencarian semua tanggal: tanggal di bawah nomor faktur.
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = AppTypography.subheadline.copyWith(
      color: c.label,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final muted = style.copyWith(color: c.labelSecondary);
    return PressableScale(
      onPressed: () => showSaleDetailSheet(context, sale),
      pressedScale: 1,
      borderRadius: AppRadius.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            _cell(
              _cols[0].$2,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.invoiceNo,
                    style: style.copyWith(fontWeight: FontWeight.w500),
                  ),
                  if (showDate)
                    Text(
                      Fmt.dateShort(sale.date),
                      style: AppTypography.caption.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                  if (_status(sale) case final status?)
                    Text(
                      status,
                      style: AppTypography.caption.copyWith(
                        color: _statusColor(c, sale),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            _cell(
              _cols[1].$2,
              Text(DateFormat('HH:mm').format(sale.date), style: muted),
            ),
            _cell(
              null,
              Text(
                sale.cashierName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
            _cell(
              _cols[3].$2,
              Text(
                '${sale.itemCount}',
                textAlign: TextAlign.right,
                style: muted,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _cell(
              _cols[4].$2! - AppSpacing.md,
              Text(
                sale.paymentMethod,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ),
            _cell(
              _cols[5].$2,
              Text(
                Fmt.rupiah(sale.total),
                textAlign: TextAlign.right,
                style: style.copyWith(
                  fontWeight: FontWeight.w600,
                  color: sale.isReturn ? c.danger : null,
                  decoration: sale.isFullyReturned
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            _cell(
              _cols[6].$2,
              Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 14,
                  color: c.labelTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Baris faktur versi HP.
class _CompactSaleRow extends StatelessWidget {
  const _CompactSaleRow({required this.sale, this.showDate = false});

  final SaleSummary sale;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = _status(sale);
    return PressableScale(
      onPressed: () => showSaleDetailSheet(context, sale),
      pressedScale: 1,
      borderRadius: AppRadius.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.invoiceNo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.subheadline.copyWith(
                      color: c.label,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${showDate ? '${Fmt.dateShort(sale.date)} ' : ''}'
                    '${DateFormat('HH:mm').format(sale.date)} · '
                    '${sale.cashierName} · ${sale.paymentMethod}'
                    '${status == null ? '' : ' · $status'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: status == null
                          ? c.labelSecondary
                          : _statusColor(c, sale),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              Fmt.rupiah(sale.total),
              style: AppTypography.subheadline.copyWith(
                color: sale.isReturn ? c.danger : c.label,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                decoration: sale.isFullyReturned
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Label status retur di bawah nomor faktur.
String? _status(SaleSummary sale) => sale.isReturn
    ? 'Nota retur'
    : sale.isFullyReturned
    ? 'Dibatalkan'
    : sale.isPartlyReturned
    ? 'Diretur sebagian'
    : sale.isExchange
    ? 'Tukar barang'
    : null;

Color _statusColor(AppColors c, SaleSummary sale) =>
    sale.isExchange && !sale.isFullyReturned && !sale.isPartlyReturned
    ? c.accent
    : sale.isPartlyReturned
    ? c.warning
    : c.danger;
