import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/device.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/number_input.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../auth/domain/permission.dart';
import '../../../payments/data/payment_method_repository.dart';
import '../../../payments/domain/payment_method.dart';
import '../../../payments/presentation/payment_method_icon.dart';
import '../../../receipt/data/printer_failure.dart';
import '../../../receipt/data/receipt_printer.dart';
import '../../../receipt/data/receipt_settings_repository.dart';
import '../../../stores/presentation/store_scope.dart';
import '../../data/checkout_service.dart';
import '../../domain/cart.dart';
import '../../domain/cash_suggestions.dart';
import '../../domain/split_payment.dart';

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

  /// Bayar terpisah (split payment): metode yang dipilih, urut dipilih.
  bool _split = false;
  final _splitMethods = <PaymentMethod>[];
  final _splitAmount = <int, TextEditingController>{};
  final _splitRef = <int, TextEditingController>{};

  int get _total => widget.cart.total;
  int get _paidValue => (parseIdNumber(_paid.text) ?? 0).round();
  bool get _isCash => _method?.isCash ?? true;
  bool get _paidEmpty => _paid.text.isEmpty;
  bool get _canSubmit => _split
      ? _splitPlan().error == null
      : _method != null && (!_isCash || _paidEmpty || _paidValue >= _total);

  @override
  void dispose() {
    _paid.dispose();
    _paidFocus.dispose();
    _ref.dispose();
    _refFocus.dispose();
    for (final c in [..._splitAmount.values, ..._splitRef.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleSplit(List<PaymentMethod> all) => setState(() {
    _split = !_split;
    _error = null;
    if (_split && _splitMethods.isEmpty) {
      // Mulai dari metode yang sedang dipilih + satu metode lain.
      final first = _method ?? all.first;
      _splitMethods.add(first);
      final other = all.firstWhere(
        (m) => m.id != first.id && m.isCash != first.isCash,
        orElse: () => all.firstWhere((m) => m.id != first.id),
      );
      _splitMethods.add(other);
    }
  });

  void _toggleSplitMethod(PaymentMethod m) => setState(() {
    _error = null;
    final i = _splitMethods.indexWhere((x) => x.id == m.id);
    if (i != -1) {
      _splitMethods.removeAt(i);
      return;
    }
    if (m.isCash && _splitMethods.any((x) => x.isCash)) {
      _error = 'Hanya boleh satu bagian tunai.';
      return;
    }
    _splitMethods.add(m);
  });

  /// Mengisi bagian [m] dengan sisa tagihan (total − bagian lain).
  void _fillRest(PaymentMethod m) {
    var others = 0;
    for (final x in _splitMethods) {
      if (x.id == m.id) continue;
      others += parseIdNumber(_amountOf(x).text)?.round() ?? 0;
    }
    final rest = _total - others;
    if (rest <= 0) return;
    final text = Fmt.number(rest);
    _amountOf(m).value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() => _error = null);
  }

  TextEditingController _amountOf(PaymentMethod m) =>
      _splitAmount.putIfAbsent(m.id, TextEditingController.new);

  TextEditingController _refOf(PaymentMethod m) =>
      _splitRef.putIfAbsent(m.id, TextEditingController.new);

  /// Bagian split dari isian. Satu kolom jumlah yang kosong = sisa tagihan.
  ({List<PaymentPart> parts, String? error, int change, int rest})
  _splitPlan() {
    final amounts = {
      for (final m in _splitMethods)
        m.id: parseIdNumber(_amountOf(m).text)?.round(),
    };
    final empty = amounts.values.where((v) => v == null).length;
    final filled = amounts.values.fold<int>(0, (s, v) => s + (v ?? 0));
    final rest = _total - filled;
    final parts = [
      for (final m in _splitMethods)
        PaymentPart(
          methodId: m.id,
          name: m.name,
          isCash: m.isCash,
          amount: amounts[m.id] ?? (empty == 1 && rest > 0 ? rest : 0),
          ref: m.isCash ? null : _refOf(m).text,
        ),
    ];
    try {
      final r = SplitPayment.settle(parts, _total);
      return (parts: parts, error: null, change: r.change, rest: 0);
    } on SplitPaymentFailure catch (e) {
      return (parts: parts, error: e.message, change: 0, rest: rest);
    }
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

  Future<void> _submitSplit() async {
    final plan = _splitPlan();
    if (_saving) return;
    if (plan.error != null) {
      setState(() => _error = plan.error);
      return;
    }
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
            storeId: ref.read(storeScopeProvider)!,
            split: plan.parts,
          );
      if (mounted) Navigator.pop(context, result);
    } on CheckoutFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    if (_split) return _submitSplit();
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
            storeId: ref.read(storeScopeProvider)!,
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
                if (widget.cart.discount > 0) ...[
                  _AmountRow(
                    label: 'Subtotal',
                    value: Fmt.rupiah(widget.cart.subtotal),
                  ),
                  _AmountRow(
                    label: 'Voucher ${widget.cart.voucher!.code}',
                    value: '− ${Fmt.rupiah(widget.cart.discount)}',
                    color: c.success,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
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
                          selected: _split
                              ? _splitMethods.any((x) => x.id == m.id)
                              : m.id == _method?.id,
                          onTap: _saving
                              ? null
                              : () => _split
                                    ? _toggleSplitMethod(m)
                                    : _selectMethod(m),
                        ),
                    ],
                  ),
          ),
          if (list.length >= 2) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: _split
                    ? 'Bayar dengan satu metode'
                    : 'Bayar terpisah (beberapa metode)',
                icon: _split
                    ? CupertinoIcons.minus_circle
                    : CupertinoIcons.square_split_2x1,
                variant: AppButtonVariant.plain,
                size: AppButtonSize.small,
                onPressed: _saving ? null : () => _toggleSplit(list),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          AnimatedSize(
            duration: AppDurations.medium,
            curve: SpringCurve.smooth,
            alignment: Alignment.topCenter,
            child: _split
                ? _splitSection(c, tabular)
                : _isCash
                ? _cashSection(c, tabular)
                : _nonCashSection(c),
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
            _isCash && !_split
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

  Widget _splitSection(AppColors c, List<FontFeature> tabular) {
    final plan = _splitPlan();
    final fieldStyle = AppTypography.body.copyWith(
      color: c.label,
      fontFeatures: tabular,
    );
    final decoration = BoxDecoration(
      color: c.fill,
      borderRadius: AppRadius.mdAll,
    );
    const pad = EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.sm + 2,
    );
    final Color tone;
    final String label;
    final int value;
    if (plan.error == null) {
      tone = c.success;
      label = 'Kembalian';
      value = plan.change;
    } else if (plan.rest > 0) {
      tone = c.danger;
      label = 'Kurang';
      value = plan.rest;
    } else {
      tone = c.warning;
      label = plan.error!;
      value = 0;
    }
    return Column(
      key: const ValueKey('split'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Label('Jumlah per metode (satu kolom kosong = sisa tagihan)'),
        for (final m in _splitMethods) ...[
          Row(
            children: [
              SizedBox(
                width: 132,
                child: Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.subheadline.copyWith(
                    color: c.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: CupertinoTextField(
                  key: ValueKey('split-amount-${m.id}'),
                  controller: _amountOf(m),
                  enabled: !_saving,
                  placeholder: m.isCash ? 'Uang diterima' : 'Jumlah',
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _submit(),
                  style: fieldStyle,
                  placeholderStyle: AppTypography.body.copyWith(
                    color: c.labelTertiary,
                  ),
                  padding: pad,
                  prefix: Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.md),
                    child: Text(
                      'Rp',
                      style: AppTypography.body.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                  ),
                  decoration: decoration,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppButton(
                key: ValueKey('split-rest-${m.id}'),
                label: 'Sisa',
                variant: AppButtonVariant.gray,
                size: AppButtonSize.small,
                onPressed: _saving ? null : () => _fillRest(m),
              ),
            ],
          ),
          if (!m.isCash) ...[
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.only(left: 132),
              child: CupertinoTextField(
                controller: _refOf(m),
                enabled: !_saving,
                placeholder: 'No. referensi ${m.name} (opsional)',
                onSubmitted: (_) => _submit(),
                style: AppTypography.subheadline.copyWith(color: c.label),
                placeholderStyle: AppTypography.subheadline.copyWith(
                  color: c.labelTertiary,
                ),
                padding: pad,
                decoration: decoration,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
        ],
        if (_splitMethods.length < 2)
          Text(
            'Ketuk metode di atas untuk menambah bagian pembayaran.',
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: 0.1),
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.headline.copyWith(color: c.label),
                ),
              ),
              if (plan.error == null || plan.rest > 0)
                Text(
                  Fmt.rupiah(value),
                  style: AppTypography.title2.copyWith(
                    color: tone,
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
            Flexible(
              child: Text(
                method.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.subheadline.copyWith(
                  color: c.label,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
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
/// dan metode bayar. Saat muncul, struk dicetak otomatis dan laci dibuka
/// (sesuai Pengaturan › Struk & Printer). Enter menutup untuk transaksi
/// berikutnya; Ctrl+P mencetak (ulang) struk.
Future<void> showCheckoutSuccessDialog(
  BuildContext context,
  CheckoutResult result,
) {
  return AppDialogs.popup<void>(
    context,
    maxWidth: 440,
    // Fokus harus di dalam CallbackShortcuts agar Enter tertangkap.
    autofocusRoot: false,
    builder: (ctx) => _SuccessView(result: result),
  );
}

enum _PrintState { idle, working, printed, drawerOpened, failed }

class _SuccessView extends ConsumerStatefulWidget {
  const _SuccessView({required this.result});

  final CheckoutResult result;

  @override
  ConsumerState<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends ConsumerState<_SuccessView> {
  _PrintState _print = _PrintState.idle;
  String? _error;

  /// Struk sudah pernah tercetak: cetak berikutnya diberi tanda cetak ulang.
  bool _printedOnce = false;

  @override
  void initState() {
    super.initState();
    _afterCheckout();
  }

  Future<void> _afterCheckout() async {
    setState(() => _print = _PrintState.working);
    try {
      final done = await ref
          .read(receiptPrinterProvider)
          .afterCheckout(widget.result.saleId, isCash: widget.result.isCash);
      if (!mounted) return;
      setState(() {
        _printedOnce = done == AfterCheckout.printed;
        _print = switch (done) {
          AfterCheckout.nothing => _PrintState.idle,
          AfterCheckout.printed => _PrintState.printed,
          AfterCheckout.drawerOpened => _PrintState.drawerOpened,
        };
      });
    } on PrinterFailure catch (e) {
      _fail(e.message);
    }
  }

  /// Cetak pertama selalu boleh; cetak ulang butuh hak "Cetak ulang struk".
  bool get _canPrint =>
      !_printedOnce ||
      (ref.read(authControllerProvider)?.can(Permission.reprintReceipt) ??
          false);

  Future<void> _printReceipt() async {
    if (_print == _PrintState.working || !_canPrint) return;
    setState(() => _print = _PrintState.working);
    try {
      await ref
          .read(receiptPrinterProvider)
          .printSale(widget.result.saleId, reprint: _printedOnce);
      if (!mounted) return;
      setState(() {
        _printedOnce = true;
        _print = _PrintState.printed;
      });
    } on PrinterFailure catch (e) {
      _fail(e.message);
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _print = _PrintState.failed;
      _error = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final result = widget.result;
    final hasChange = result.change > 0;
    // Tukar barang: kredit nota retur ikut membayar; [money] = uang dari
    // pelanggan.
    final exchange = result.credit > 0;
    final money = result.paid - result.credit;
    final printerReady =
        ref.watch(printerConfigProvider).value?.isReady ?? false;
    void close() => Navigator.pop(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): close,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): close,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            _printReceipt,
        const SingleActivator(LogicalKeyboardKey.keyP, meta: true):
            _printReceipt,
      },
      child: Focus(
        autofocus: true,
        child: Padding(
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
                builder: (_, s, child) =>
                    Transform.scale(scale: s, child: child),
                child: Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  size: 72,
                  color: c.success,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                exchange ? 'Tukar Berhasil' : 'Transaksi Berhasil',
                style: AppTypography.title2.copyWith(color: c.label),
              ),
              Text(
                '${result.invoiceNo} · ${result.paymentMethod}',
                style: AppTypography.subheadline.copyWith(
                  color: c.labelSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                hasChange
                    ? (exchange && money == 0
                          ? 'Kembalikan ke pelanggan'
                          : 'Kembalian')
                    : exchange
                    ? 'Dibayar pelanggan'
                    : 'Total dibayar',
                style: AppTypography.subheadline.copyWith(
                  color: c.labelSecondary,
                ),
              ),
              Text(
                Fmt.rupiah(
                  hasChange
                      ? result.change
                      : exchange
                      ? money
                      : result.total,
                ),
                style: AppTypography.displayAmount.copyWith(
                  color: hasChange ? c.success : c.label,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  'Total ${Fmt.rupiah(result.total)}',
                  if (exchange) 'Kredit tukar −${Fmt.rupiah(result.credit)}',
                  if (hasChange && money > 0) 'Dibayar ${Fmt.rupiah(money)}',
                ].join(' · '),
                textAlign: TextAlign.center,
                style: AppTypography.footnote.copyWith(color: c.labelSecondary),
              ),
              if (_print != _PrintState.idle) ...[
                const SizedBox(height: AppSpacing.md),
                _PrintStatus(state: _print, error: _error),
              ],
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: Device.withShortcut('Transaksi Baru', 'Enter'),
                size: AppButtonSize.large,
                expand: true,
                onPressed: close,
              ),
              if (printerReady && _canPrint) ...[
                const SizedBox(height: AppSpacing.xs),
                AppButton(
                  label: _printedOnce
                      ? 'Cetak Ulang Struk  (Ctrl+P)'
                      : 'Cetak Struk  (Ctrl+P)',
                  icon: CupertinoIcons.printer,
                  variant: AppButtonVariant.gray,
                  expand: true,
                  loading: _print == _PrintState.working,
                  onPressed: _printReceipt,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PrintStatus extends StatelessWidget {
  const _PrintStatus({required this.state, this.error});

  final _PrintState state;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, color, text) = switch (state) {
      _PrintState.working => (
        CupertinoIcons.printer,
        c.labelSecondary,
        'Mencetak struk…',
      ),
      _PrintState.printed => (
        CupertinoIcons.checkmark_alt,
        c.success,
        'Struk dicetak',
      ),
      _PrintState.drawerOpened => (
        CupertinoIcons.tray_arrow_down,
        c.success,
        'Laci dibuka',
      ),
      _PrintState.failed => (
        CupertinoIcons.exclamationmark_triangle_fill,
        c.danger,
        'Struk gagal dicetak: ${error ?? ''}',
      ),
      _PrintState.idle => (CupertinoIcons.printer, c.labelSecondary, ''),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              text,
              style: AppTypography.footnote.copyWith(color: c.label),
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris kecil "label ...... nilai" di ringkasan tagihan.
class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.subheadline.copyWith(
      color: color ?? context.colors.labelSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Text(value, style: style),
        ],
      ),
    );
  }
}
