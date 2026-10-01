import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/stat_card.dart';
import '../../../../core/widgets/state_views.dart';
import '../../data/sales_repository.dart';
import '../../domain/sale.dart';
import 'sale_detail_sheet.dart';

/// Transaksi hari ini, diperbarui otomatis setiap ada penjualan baru.
final todaySalesProvider = StreamProvider.autoDispose<List<SaleSummary>>(
  (ref) => ref.watch(salesRepositoryProvider).watchDay(DateTime.now()),
);

const _cols = <(String, double?, TextAlign)>[
  ('No. Faktur', 190, TextAlign.left),
  ('Jam', 70, TextAlign.left),
  ('Kasir', null, TextAlign.left),
  ('Barang', 80, TextAlign.right),
  ('Potongan', 120, TextAlign.right),
  ('Total', 140, TextAlign.right),
  ('', 32, TextAlign.right),
];

/// Tab "Hari Ini": ringkasan dan daftar faktur hari ini.
class TodaySalesView extends ConsumerWidget {
  const TodaySalesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(todaySalesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
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
          children: [
            _Summary(sales: list),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: _SalesTable(sales: list)),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.sales});

  final List<SaleSummary> sales;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final omzet = sales.fold<int>(0, (s, e) => s + e.total);
    final average = sales.isEmpty ? 0 : (omzet / sales.length).round();
    final cards = [
      StatCard(
        label: 'Transaksi',
        value: Fmt.number(sales.length),
        icon: CupertinoIcons.doc_text_fill,
        color: c.accent,
      ),
      StatCard(
        label: 'Omzet Hari Ini',
        value: Fmt.rupiah(omzet),
        icon: CupertinoIcons.money_dollar_circle_fill,
        color: c.success,
      ),
      StatCard(
        label: 'Rata-rata per Transaksi',
        value: Fmt.rupiah(average),
        icon: CupertinoIcons.chart_bar_fill,
        color: c.warning,
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          Expanded(child: cards[i]),
        ],
      ],
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
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Row(
              children: [
                for (final (label, width, align) in _cols)
                  _cell(
                    width,
                    Text(label.toUpperCase(), textAlign: align, style: header),
                  ),
              ],
            ),
          ),
          Container(height: 0.5, color: c.separator),
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
                    itemBuilder: (context, i) => _SaleRow(sale: sales[i]),
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
              Text(
                sale.invoiceNo,
                style: style.copyWith(fontWeight: FontWeight.w500),
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
            _cell(
              _cols[4].$2,
              Text(
                sale.discount == 0 ? '–' : Fmt.number(sale.discount),
                textAlign: TextAlign.right,
                style: sale.discount == 0
                    ? muted
                    : style.copyWith(color: c.danger),
              ),
            ),
            _cell(
              _cols[5].$2,
              Text(
                Fmt.rupiah(sale.total),
                textAlign: TextAlign.right,
                style: style.copyWith(fontWeight: FontWeight.w600),
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
