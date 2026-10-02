import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../receipt/data/printer_failure.dart';
import '../../../receipt/data/receipt_printer.dart';
import '../../../receipt/data/receipt_settings_repository.dart';
import '../../data/sales_repository.dart';
import '../../domain/sale.dart';

/// Rincian satu faktur: barang, potongan, pembayaran.
Future<void> showSaleDetailSheet(BuildContext context, SaleSummary sale) {
  return AppDialogs.sheet<void>(
    context,
    title: sale.invoiceNo,
    maxWidth: 620,
    builder: (_) => _SaleDetail(sale: sale),
  );
}

final _saleLinesProvider = FutureProvider.autoDispose
    .family<List<SaleLine>, int>(
      (ref, id) => ref.watch(salesRepositoryProvider).linesOf(id),
    );

class _SaleDetail extends ConsumerWidget {
  const _SaleDetail({required this.sale});

  final SaleSummary sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final lines = ref.watch(_saleLinesProvider(sale.id));
    final num = const [FontFeature.tabularFigures()];
    final body = AppTypography.subheadline.copyWith(
      color: c.label,
      fontFeatures: num,
    );
    final muted = body.copyWith(color: c.labelSecondary);

    Widget row(String label, String value, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label, style: style ?? muted),
          const Spacer(),
          Text(value, style: style ?? body),
        ],
      ),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${Fmt.dateTime(sale.date)} · Kasir: ${sale.cashierName}',
            style: muted,
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: c.fillSecondary,
              borderRadius: AppRadius.mdAll,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            child: lines.when(
              loading: () => const SizedBox(height: 80, child: LoadingState()),
              error: (e, _) => ErrorBanner(message: '$e'),
              data: (items) => Column(
                children: [
                  for (final (i, l) in items.indexed) ...[
                    if (i > 0) Container(height: 0.5, color: c.separator),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.name,
                                  style: body.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '${Fmt.number(l.qty)} ${l.unitName ?? ''} × '
                                  '${Fmt.rupiah(l.price)}'
                                  '${l.discountPercent > 0 ? ' · pot. ${Fmt.number(l.discountPercent)}%' : ''}',
                                  style: AppTypography.footnote.copyWith(
                                    color: c.labelSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(Fmt.rupiah(l.subtotal), style: body),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          row('Subtotal', Fmt.rupiah(sale.subtotal)),
          if (sale.discount > 0)
            row(
              sale.discountPercent == null
                  ? 'Potongan'
                  : 'Potongan (${Fmt.number(sale.discountPercent!)}%)',
              '− ${Fmt.rupiah(sale.discount)}',
            ),
          row(
            'Total',
            Fmt.rupiah(sale.total),
            style: AppTypography.headline.copyWith(
              color: c.label,
              fontFeatures: num,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Container(height: 0.5, color: c.separator),
          ),
          row('Dibayar (${sale.paymentMethod})', Fmt.rupiah(sale.paid)),
          if (sale.paymentRef != null) row('No. referensi', sale.paymentRef!),
          if (sale.change > 0) row('Kembalian', Fmt.rupiah(sale.change)),
          if (ref.watch(printerConfigProvider).value?.isReady ?? false) ...[
            const SizedBox(height: AppSpacing.lg),
            _ReprintButton(saleId: sale.id),
          ],
        ],
      ),
    );
  }
}

/// Mencetak ulang struk faktur (diberi tanda "CETAK ULANG").
class _ReprintButton extends ConsumerStatefulWidget {
  const _ReprintButton({required this.saleId});

  final int saleId;

  @override
  ConsumerState<_ReprintButton> createState() => _ReprintButtonState();
}

class _ReprintButtonState extends ConsumerState<_ReprintButton> {
  bool _printing = false;
  String? _error;

  Future<void> _print() async {
    setState(() {
      _printing = true;
      _error = null;
    });
    try {
      await ref
          .read(receiptPrinterProvider)
          .printSale(widget.saleId, reprint: true);
    } on PrinterFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          ErrorBanner(message: _error!),
          const SizedBox(height: AppSpacing.sm),
        ],
        AppButton(
          label: 'Cetak Ulang Struk',
          icon: CupertinoIcons.printer,
          variant: AppButtonVariant.tinted,
          expand: true,
          loading: _printing,
          onPressed: _print,
        ),
      ],
    );
  }
}
