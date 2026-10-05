import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../stores/presentation/store_scope.dart';
import '../../data/sales_repository.dart';
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

/// Tab "Hari Ini": daftar faktur hari ini (tanpa ringkasan angka).
class TodaySalesView extends ConsumerWidget {
  const TodaySalesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(todaySalesProvider);
    return Padding(
      padding: AppBreakpoints.isCompact(context)
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
      child: sales.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorBanner(message: 'Gagal memuat transaksi: $e'),
        data: (list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Expanded(child: _SalesTable(sales: list))],
        ),
      ),
    );
  }
}

class _SalesTable extends StatelessWidget {
  const _SalesTable({required this.sales});

  final List<SaleSummary> sales;

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
                ? const EmptyState(
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
                        ? _CompactSaleRow(sale: sales[i])
                        : _SaleRow(sale: sales[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

Widget _cell(double? width, Widget child) => width == null
    ? Expanded(child: child)
    : SizedBox(width: width, child: child);

class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.sale});

  final SaleSummary sale;

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
                  if (_status(sale) case final status?)
                    Text(
                      status,
                      style: AppTypography.caption.copyWith(
                        color: sale.isPartlyReturned ? c.warning : c.danger,
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
  const _CompactSaleRow({required this.sale});

  final SaleSummary sale;

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
                    '${DateFormat('HH:mm').format(sale.date)} · '
                    '${sale.cashierName} · ${sale.paymentMethod}'
                    '${status == null ? '' : ' · $status'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: status == null
                          ? c.labelSecondary
                          : sale.isPartlyReturned
                          ? c.warning
                          : c.danger,
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
    : null;
