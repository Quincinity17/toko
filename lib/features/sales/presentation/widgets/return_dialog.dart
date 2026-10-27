import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/number_input.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../receipt/data/printer_failure.dart';
import '../../../receipt/data/receipt_printer.dart';
import '../../data/return_service.dart';
import '../../domain/sale.dart';
import '../../domain/sale_return.dart';
import 'exchange_dialog.dart';

/// Popup retur sebagian / batal seluruh faktur [sale]. Mengembalikan nota
/// retur yang tersimpan ([ReturnResult]), permintaan tukar barang
/// ([ExchangeRequest], belum tersimpan), atau `null` bila dibatalkan.
Future<Object?> showReturnDialog(BuildContext context, SaleSummary sale) {
  return AppDialogs.popup<Object>(
    context,
    title: 'Retur ${sale.invoiceNo}',
    maxWidth: 600,
    autofocusRoot: false,
    builder: (_) => _ReturnForm(saleId: sale.id),
  );
}

final _returnableProvider = FutureProvider.autoDispose
    .family<ReturnableSale, int>(
      (ref, id) => ref.watch(returnServiceProvider).load(id),
    );

class _ReturnForm extends ConsumerStatefulWidget {
  const _ReturnForm({required this.saleId});

  final int saleId;

  @override
  ConsumerState<_ReturnForm> createState() => _ReturnFormState();
}

class _ReturnFormState extends ConsumerState<_ReturnForm> {
  final _qty = <int, TextEditingController>{};
  final _reason = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    _reason.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(ReturnableLine l, bool discounted) =>
      _qty.putIfAbsent(
        l.saleItemId,
        // Faktur berpotongan hanya bisa batal semua: langsung terisi penuh.
        () => TextEditingController(text: discounted ? _fmt(l.returnable) : ''),
      );

  static String _fmt(double v) => v <= 0 ? '' : Fmt.number(v);

  Map<int, double> get _qtys => {
    for (final MapEntry(:key, :value) in _qty.entries)
      key: (parseIdNumber(value.text) ?? 0).toDouble(),
  };

  void _setAll(ReturnableSale sale, {required bool all}) => setState(() {
    for (final l in sale.lines) {
      _qty[l.saleItemId]!.text = all ? _fmt(l.returnable) : '';
    }
    _error = null;
  });

  void _step(ReturnableLine l, double delta) {
    final c = _qty[l.saleItemId]!;
    final now = (parseIdNumber(c.text) ?? 0).toDouble();
    final next = (now + delta).clamp(0, l.returnable).toDouble();
    setState(() {
      c.text = _fmt(next);
      _error = null;
    });
  }

  Future<void> _submit(ReturnableSale sale) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(returnServiceProvider)
          .create(
            actor: ref.read(authControllerProvider)!,
            saleId: sale.saleId,
            qtys: _qtys,
            reason: _reason.text,
          );
      // Struk nota retur dicetak (bila cetak otomatis) dan laci dibuka untuk
      // uang tunai yang dikembalikan (bila diatur).
      try {
        await ref
            .read(receiptPrinterProvider)
            .afterCheckout(result.saleId, isCash: result.isCash);
      } on PrinterFailure {
        // Retur tetap tersimpan; struk bisa dicetak dari rincian nota retur,
        // laci bisa dibuka manual (F6).
      }
      if (mounted) Navigator.pop(context, result);
    } on ReturnFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Lanjut ke tukar barang: pilihan & alasan diperiksa dulu, lalu popup
  /// ini ditutup dengan [ExchangeRequest] (belum ada yang tersimpan).
  Future<void> _toExchange(ReturnableSale sale) async {
    setState(() => _error = null);
    try {
      final credit = await ref
          .read(returnServiceProvider)
          .check(
            actor: ref.read(authControllerProvider)!,
            saleId: sale.saleId,
            qtys: _qtys,
            reason: _reason.text,
          );
      if (sale.storeId == null) {
        throw const ReturnFailure('Faktur ini tidak punya toko.');
      }
      if (!mounted) return;
      Navigator.pop(
        context,
        ExchangeRequest(
          saleId: sale.saleId,
          invoiceNo: sale.invoiceNo,
          storeId: sale.storeId!,
          qtys: _qtys,
          reason: _reason.text.trim(),
          credit: credit,
          itemCount: _qtys.values.where((q) => q > 0).length,
        ),
      );
    } on ReturnFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final async = ref.watch(_returnableProvider(widget.saleId));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: async.when(
        loading: () => const SizedBox(height: 160, child: LoadingState()),
        error: (e, _) =>
            ErrorBanner(message: e is ReturnFailure ? e.message : '$e'),
        data: (sale) => _form(c, sale),
      ),
    );
  }

  Widget _form(AppColors c, ReturnableSale sale) {
    final discounted = sale.hasDiscount;
    final lines = [
      for (final l in sale.lines)
        if (l.returnable > 1e-9) l,
    ];
    for (final l in sale.lines) {
      _controllerFor(l, discounted);
    }
    final refund = sale.refundFor(_qtys);
    final anyPicked = _qtys.values.any((q) => q > 0);
    final muted = AppTypography.footnote.copyWith(color: c.labelSecondary);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          discounted
              ? 'Faktur dengan voucher/potongan hanya bisa dibatalkan seluruhnya.'
              : 'Isi jumlah barang yang dikembalikan pelanggan. Stok barang '
                    'kembali, dan uang dikembalikan lewat ${sale.paymentMethod}.',
          style: muted,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            AppButton(
              label: 'Batalkan Semua',
              icon: CupertinoIcons.arrow_uturn_left,
              variant: AppButtonVariant.tinted,
              size: AppButtonSize.small,
              destructive: true,
              onPressed: () => _setAll(sale, all: true),
            ),
            if (!discounted) ...[
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                label: 'Kosongkan',
                variant: AppButtonVariant.plain,
                size: AppButtonSize.small,
                onPressed: () => _setAll(sale, all: false),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          constraints: const BoxConstraints(maxHeight: 320),
          decoration: BoxDecoration(
            color: c.fillSecondary,
            borderRadius: AppRadius.mdAll,
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            itemCount: lines.length,
            separatorBuilder: (_, _) =>
                Container(height: 0.5, color: c.separator),
            itemBuilder: (_, i) => _lineRow(c, lines[i], discounted),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          controller: _reason,
          label: 'Alasan',
          placeholder: 'mis. barang rusak, salah input, pelanggan batal',
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          ErrorBanner(message: _error!),
        ],
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: 'Tukar dengan Barang Lain',
          icon: CupertinoIcons.arrow_2_squarepath,
          variant: AppButtonVariant.tinted,
          expand: true,
          onPressed: anyPicked && !_saving ? () => _toExchange(sale) : null,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Batal',
                variant: AppButtonVariant.gray,
                expand: true,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: anyPicked
                    ? 'Kembalikan ${Fmt.rupiah(refund)}'
                    : 'Pilih barang',
                icon: CupertinoIcons.arrow_uturn_left,
                destructive: true,
                expand: true,
                loading: _saving,
                onPressed: anyPicked ? () => _submit(sale) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _lineRow(AppColors c, ReturnableLine l, bool discounted) {
    final controller = _qty[l.saleItemId]!;
    final unit = l.unitName ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.name,
                  style: AppTypography.subheadline.copyWith(
                    color: c.label,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Terjual ${Fmt.number(l.soldQty)} $unit × '
                  '${Fmt.rupiah(l.price)}'
                  '${l.returnedQty > 0 ? ' · sudah diretur ${Fmt.number(l.returnedQty)}' : ''}',
                  style: AppTypography.footnote.copyWith(
                    color: c.labelSecondary,
                  ),
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: CupertinoIcons.minus,
            onPressed: discounted ? null : () => _step(l, -1),
          ),
          SizedBox(
            width: 64,
            child: CupertinoTextField(
              controller: controller,
              enabled: !discounted,
              textAlign: TextAlign.center,
              placeholder: '0',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: AppTypography.subheadline.copyWith(color: c.label),
              onChanged: (_) => setState(() => _error = null),
            ),
          ),
          AppIconButton(
            icon: CupertinoIcons.plus,
            onPressed: discounted ? null : () => _step(l, 1),
          ),
        ],
      ),
    );
  }
}
