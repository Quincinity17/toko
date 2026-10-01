import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/number_input.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../data/checkout_service.dart';
import '../../domain/cart.dart';
import '../../domain/cash_suggestions.dart';

/// Sheet pembayaran tunai. Menyimpan transaksi lalu mengembalikan hasilnya,
/// atau `null` jika dibatalkan.
Future<CheckoutResult?> showPaymentSheet(BuildContext context, Cart cart) {
  return AppDialogs.sheet<CheckoutResult>(
    context,
    title: 'Pembayaran',
    maxWidth: 520,
    builder: (_) => _PaymentForm(cart: cart),
  );
}

class _PaymentForm extends ConsumerStatefulWidget {
  const _PaymentForm({required this.cart});

  final Cart cart;

  @override
  ConsumerState<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends ConsumerState<_PaymentForm> {
  final _paid = TextEditingController();
  bool _saving = false;
  String? _error;

  int get _total => widget.cart.total;
  int get _paidValue => (parseIdNumber(_paid.text) ?? 0).round();
  bool get _enough => _paidValue >= _total;

  @override
  void dispose() {
    _paid.dispose();
    super.dispose();
  }

  void _setPaid(int value) {
    final text = Fmt.number(value);
    _paid.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {});
  }

  Future<void> _submit() async {
    if (_saving) return;
    // Kolom kosong + Enter = uang pas.
    if (_paid.text.isEmpty) _setPaid(_total);
    if (!_enough) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(checkoutServiceProvider)
          .checkout(
            cart: widget.cart,
            cashier: ref.read(authControllerProvider)!,
            paid: _paidValue,
          );
      if (mounted) Navigator.pop(context, result);
    } on CheckoutFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final change = _paidValue - _total;
    final num = const [FontFeature.tabularFigures()];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Total belanja',
            style: AppTypography.subheadline.copyWith(color: c.labelSecondary),
          ),
          Text(
            Fmt.rupiah(_total),
            style: AppTypography.displayAmount.copyWith(color: c.label),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Uang diterima (tunai)',
            style: AppTypography.footnote.copyWith(
              color: c.labelSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs - 2),
          CupertinoTextField(
            controller: _paid,
            autofocus: true,
            enabled: !_saving,
            placeholder: Fmt.number(_total),
            keyboardType: TextInputType.number,
            inputFormatters: [RupiahInputFormatter()],
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
            style: AppTypography.title2.copyWith(
              color: c.label,
              fontFeatures: num,
            ),
            placeholderStyle: AppTypography.title2.copyWith(
              color: c.labelTertiary,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            prefix: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: Text(
                'Rp',
                style: AppTypography.title3.copyWith(color: c.labelSecondary),
              ),
            ),
            decoration: BoxDecoration(
              color: c.fill,
              borderRadius: AppRadius.mdAll,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _CashChip(
                label: 'Uang Pas',
                selected: _paidValue == _total && _paid.text.isNotEmpty,
                onTap: () => _setPaid(_total),
              ),
              for (final v in cashSuggestions(_total))
                _CashChip(
                  label: Fmt.number(v),
                  selected: _paidValue == v,
                  onTap: () => _setPaid(v),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: (_paid.text.isEmpty || _enough ? c.success : c.danger)
                  .withValues(alpha: 0.1),
              borderRadius: AppRadius.mdAll,
            ),
            child: Row(
              children: [
                Text(
                  _paid.text.isEmpty || _enough ? 'Kembalian' : 'Kurang',
                  style: AppTypography.headline.copyWith(color: c.label),
                ),
                const Spacer(),
                Text(
                  _paid.text.isEmpty ? Fmt.rupiah(0) : Fmt.rupiah(change.abs()),
                  style: AppTypography.title2.copyWith(
                    color: _paid.text.isEmpty || _enough ? c.success : c.danger,
                    fontFeatures: num,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Selesaikan Transaksi',
            icon: CupertinoIcons.checkmark_alt,
            size: AppButtonSize.large,
            expand: true,
            loading: _saving,
            onPressed: _paid.text.isEmpty || _enough ? _submit : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter = selesaikan · kolom kosong + Enter = uang pas · Esc = batal',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: c.labelTertiary),
          ),
        ],
      ),
    );
  }
}

class _CashChip extends StatelessWidget {
  const _CashChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressableScale(
      onPressed: onTap,
      pressedScale: 0.94,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.fill,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: AppTypography.subheadline.copyWith(
            color: selected ? CupertinoColors.white : c.label,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Konfirmasi transaksi selesai: kembalian besar dan nomor faktur.
/// Enter atau tombol menutup sheet untuk lanjut transaksi berikutnya.
Future<void> showCheckoutSuccessSheet(
  BuildContext context,
  CheckoutResult result,
) {
  return AppDialogs.sheet<void>(
    context,
    maxWidth: 460,
    builder: (ctx) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            Navigator.pop(ctx),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            Navigator.pop(ctx),
      },
      child: Focus(autofocus: true, child: _SuccessView(result: result)),
    ),
  );
}

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.result});

  final CheckoutResult result;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1),
            duration: AppDurations.slow,
            curve: SpringCurve.bouncy,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Icon(
              CupertinoIcons.checkmark_circle_fill,
              size: 72,
              color: c.success,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Transaksi Berhasil',
            style: AppTypography.title2.copyWith(color: c.label),
          ),
          Text(
            result.invoiceNo,
            style: AppTypography.subheadline.copyWith(color: c.labelSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Kembalian',
            style: AppTypography.subheadline.copyWith(color: c.labelSecondary),
          ),
          Text(
            Fmt.rupiah(result.change),
            style: AppTypography.displayAmount.copyWith(color: c.success),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Total ${Fmt.rupiah(result.total)} · '
            'Dibayar ${Fmt.rupiah(result.paid)}',
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Transaksi Baru  (Enter)',
            size: AppButtonSize.large,
            expand: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}
