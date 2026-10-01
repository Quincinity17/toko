import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
import '../../../payments/data/payment_method_repository.dart';
import '../../../payments/domain/payment_method.dart';
import '../../../payments/presentation/payment_method_icon.dart';
import '../../data/checkout_service.dart';
import '../../domain/cart.dart';
import '../../domain/cash_suggestions.dart';

/// Popup pembayaran: pilih metode, isi uang (tunai) atau referensi
/// (non-tunai), lalu simpan. Mengembalikan hasil, atau `null` jika batal.
Future<CheckoutResult?> showPaymentDialog(BuildContext context, Cart cart) {
  return AppDialogs.popup<CheckoutResult>(
    context,
    title: 'Pembayaran',
    maxWidth: 560,
    autofocusRoot: false,
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
  final _paidFocus = FocusNode();
  final _ref = TextEditingController();
  final _refFocus = FocusNode();

  PaymentMethod? _method;
  bool _saving = false;
  String? _error;

  int get _total => widget.cart.total;
  int get _paidValue => (parseIdNumber(_paid.text) ?? 0).round();
  bool get _isCash => _method?.isCash ?? true;
  bool get _paidEmpty => _paid.text.isEmpty;
  bool get _canSubmit =>
      _method != null && (!_isCash || _paidEmpty || _paidValue >= _total);

  @override
  void dispose() {
    _paid.dispose();
    _paidFocus.dispose();
    _ref.dispose();
    _refFocus.dispose();
    super.dispose();
  }

  void _selectMethod(PaymentMethod m) {
    setState(() {
      _method = m;
      _error = null;
    });
    // Fokus ke kolom yang relevan untuk metode itu.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (m.isCash ? _paidFocus : _refFocus).requestFocus();
    });
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
    final method = _method;
    if (_saving || method == null) return;
    // Tunai: kolom kosong + Enter = uang pas.
    if (method.isCash && _paidEmpty) _setPaid(_total);
    if (!_canSubmit) return;

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
            paymentMethodId: method.id,
            paid: method.isCash ? _paidValue : null,
            paymentRef: method.isCash ? null : _ref.text,
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
    final methods = ref.watch(activePaymentMethodsProvider);
    const tabular = [FontFeature.tabularFigures()];

    // Pilih metode pertama (biasanya Tunai) secara otomatis.
    final list = methods.value ?? const <PaymentMethod>[];
    if (_method == null && list.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _method == null) _selectMethod(list.first);
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ringkasan tagihan.
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: c.fillSecondary,
              borderRadius: AppRadius.mdAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total',
                      style: AppTypography.headline.copyWith(color: c.label),
                    ),
                    const Spacer(),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          Fmt.rupiah(_total),
                          style: AppTypography.displayAmount.copyWith(
                            color: c.label,
                            fontSize: 36,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Label('Metode pembayaran'),
          methods.when(
            loading: () => const SizedBox(height: 64, child: LoadingState()),
            error: (e, _) => ErrorBanner(message: '$e'),
            data: (list) => list.isEmpty
                ? const ErrorBanner(
                    message:
                        'Belum ada metode pembayaran aktif. Minta admin '
                        'mengaktifkan di Pengaturan › Metode Pembayaran.',
                  )
                : Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final m in list)
                        _MethodChip(
                          method: m,
                          selected: m.id == _method?.id,
                          onTap: _saving ? null : () => _selectMethod(m),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AnimatedSize(
            duration: AppDurations.medium,
            curve: SpringCurve.smooth,
            alignment: Alignment.topCenter,
            child: _isCash ? _cashSection(c, tabular) : _nonCashSection(c),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Selesaikan Transaksi',
            icon: CupertinoIcons.checkmark_alt,
            size: AppButtonSize.large,
            expand: true,
            loading: _saving,
            onPressed: _canSubmit ? _submit : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _isCash
                ? 'Enter = selesaikan · kosong + Enter = uang pas · Esc = batal'
                : 'Enter = selesaikan · Esc = batal',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: c.labelTertiary),
          ),
        ],
      ),
    );
  }

  Widget _cashSection(AppColors c, List<FontFeature> tabular) {
    final change = _paidValue - _total;
    final ok = _paidEmpty || change >= 0;
    return Column(
      key: const ValueKey('cash'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label('Uang diterima'),
        CupertinoTextField(
          controller: _paid,
          focusNode: _paidFocus,
          enabled: !_saving,
          placeholder: Fmt.number(_total),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          style: AppTypography.title2.copyWith(
            color: c.label,
            fontFeatures: tabular,
          ),
          placeholderStyle: AppTypography.title2.copyWith(
            color: c.labelTertiary,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
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
              selected: !_paidEmpty && _paidValue == _total,
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
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: (ok ? c.success : c.danger).withValues(alpha: 0.1),
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            children: [
              Text(
                ok ? 'Kembalian' : 'Kurang',
                style: AppTypography.headline.copyWith(color: c.label),
              ),
              const Spacer(),
              Text(
                Fmt.rupiah(_paidEmpty ? 0 : change.abs()),
                style: AppTypography.title2.copyWith(
                  color: ok ? c.success : c.danger,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _nonCashSection(AppColors c) {
    return Column(
      key: const ValueKey('noncash'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: c.accentTint,
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            children: [
              Icon(CupertinoIcons.info_circle_fill, color: c.accent, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Pastikan pembayaran ${Fmt.rupiah(_total)} lewat '
                  '${_method?.name} sudah diterima sebelum menyelesaikan.',
                  style: AppTypography.subheadline.copyWith(color: c.label),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Label('No. referensi (opsional)'),
        CupertinoTextField(
          controller: _ref,
          focusNode: _refFocus,
          enabled: !_saving,
          placeholder: 'mis. 4 digit akhir kartu / ID transaksi',
          onSubmitted: (_) => _submit(),
          style: AppTypography.body.copyWith(color: c.label),
          placeholderStyle: AppTypography.body.copyWith(color: c.labelTertiary),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: c.fill,
            borderRadius: AppRadius.mdAll,
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: AppSpacing.xs - 2),
    child: Text(
      text,
      style: AppTypography.footnote.copyWith(
        color: context.colors.labelSecondary,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressableScale(
      onPressed: onTap,
      pressedScale: 0.95,
      borderRadius: AppRadius.mdAll,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? c.accentTint : c.fillSecondary,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: selected ? c.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              paymentMethodIcon(method),
              size: 20,
              color: selected ? c.accent : c.labelSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              method.name,
              style: AppTypography.subheadline.copyWith(
                color: c.label,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
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

/// Popup konfirmasi transaksi selesai: kembalian besar, nomor faktur,
/// dan metode bayar. Enter atau tombol menutup untuk transaksi berikutnya.
Future<void> showCheckoutSuccessDialog(
  BuildContext context,
  CheckoutResult result,
) {
  return AppDialogs.popup<void>(
    context,
    maxWidth: 440,
    // Fokus harus di dalam CallbackShortcuts agar Enter tertangkap.
    autofocusRoot: false,
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
    final hasChange = result.change > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
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
            '${result.invoiceNo} · ${result.paymentMethod}',
            style: AppTypography.subheadline.copyWith(color: c.labelSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            hasChange ? 'Kembalian' : 'Total dibayar',
            style: AppTypography.subheadline.copyWith(color: c.labelSecondary),
          ),
          Text(
            Fmt.rupiah(hasChange ? result.change : result.total),
            style: AppTypography.displayAmount.copyWith(
              color: hasChange ? c.success : c.label,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            [
              'Total ${Fmt.rupiah(result.total)}',
              if (hasChange) 'Dibayar ${Fmt.rupiah(result.paid)}',
            ].join(' · '),
            textAlign: TextAlign.center,
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
