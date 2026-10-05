import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../receipt/data/printer_failure.dart';
import '../../../receipt/data/receipt_printer.dart';
import '../../../receipt/data/receipt_settings_repository.dart';
import '../../data/return_service.dart';
import '../../data/sales_repository.dart';
import '../../domain/sale.dart';
import 'return_dialog.dart';

/// Rincian satu faktur: barang, potongan, pembayaran, retur.
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
          Expanded(child: Text(label, style: style ?? muted)),
          const SizedBox(width: AppSpacing.sm),
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
            '${Fmt.dateTime(sale.date)} · '
            '${sale.isReturn ? 'Diproses' : 'Kasir'}: ${sale.cashierName}',
            style: muted,
          ),
          if (sale.isReturn || sale.returnedAmount > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            _ReturnBanner(sale: sale),
          ],
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
          if (sale.isReturn)
            row('Dikembalikan (${sale.paymentMethod})', Fmt.rupiah(-sale.total))
          else ...[
            row('Dibayar (${sale.paymentMethod})', Fmt.rupiah(sale.paid)),
            if (sale.paymentRef != null) row('No. referensi', sale.paymentRef!),
            if (sale.change > 0) row('Kembalian', Fmt.rupiah(sale.change)),
            if (sale.returnedAmount > 0)
              row('Sudah diretur', '− ${Fmt.rupiah(sale.returnedAmount)}'),
          ],
          if (!sale.isReturn &&
              !sale.isFullyReturned &&
              ReturnService.canReturn(
                ref.watch(authControllerProvider)!,
                sale.storeId,
              )) ...[
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Retur / Batalkan',
              icon: CupertinoIcons.arrow_uturn_left,
              variant: AppButtonVariant.gray,
              destructive: true,
              expand: true,
              onPressed: () => _return(context, sale),
            ),
          ],
          // Nota retur tidak dicetak ulang sebagai struk penjualan.
          if (!sale.isReturn &&
              (ref.watch(printerConfigProvider).value?.isReady ?? false)) ...[
            const SizedBox(height: AppSpacing.sm),
            _ReprintButton(saleId: sale.id),
          ],
        ],
      ),
    );
  }
}

Future<void> _return(BuildContext context, SaleSummary sale) async {
  final result = await showReturnDialog(context, sale);
  if (result == null || !context.mounted) return;
  Navigator.pop(context); // tutup rincian (datanya sudah berubah)
  await AppDialogs.alert(
    context,
    title: 'Retur tersimpan',
    message:
        '${result.invoiceNo}\nKembalikan ${Fmt.rupiah(result.refund)} ke '
        'pelanggan (${result.paymentMethod}).',
  );
}

/// Keterangan retur: nota retur (alasan) atau faktur yang sudah diretur.
class _ReturnBanner extends StatelessWidget {
  const _ReturnBanner({required this.sale});

  final SaleSummary sale;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = sale.isReturn || sale.isFullyReturned ? c.danger : c.warning;
    final text = sale.isReturn
        ? 'Nota retur. Alasan: ${sale.returnReason ?? '–'}'
        : sale.isFullyReturned
        ? 'Faktur ini sudah dibatalkan (semua barang diretur).'
        : 'Sebagian barang sudah diretur (${Fmt.rupiah(sale.returnedAmount)}).';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.arrow_uturn_left, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypography.footnote.copyWith(color: color),
            ),
          ),
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
