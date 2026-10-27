import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/number_input.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/barcode_scanner.dart';
import '../../../../core/widgets/choice_chips.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../auth/presentation/auth_controller.dart';
import '../../../payments/data/payment_method_repository.dart';
import '../../../payments/domain/payment_method.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/domain/product.dart';
import '../../../products/domain/product_pricing.dart';
import '../../data/checkout_service.dart';
import '../../data/exchange_service.dart';
import '../../data/return_service.dart';
import '../../domain/cart.dart';
import '../../domain/split_payment.dart';
import '../../domain/exchange.dart';
import 'product_search_sheet.dart';

/// Barang yang dikembalikan untuk ditukar (hasil popup retur).
class ExchangeRequest {
  const ExchangeRequest({
    required this.saleId,
    required this.invoiceNo,
    required this.storeId,
    required this.qtys,
    required this.reason,
    required this.credit,
    required this.itemCount,
  });

  final int saleId;
  final String invoiceNo;
  final int storeId;
  final Map<int, double> qtys;
  final String reason;

  /// Nilai barang yang dikembalikan.
  final int credit;
  final int itemCount;
}

/// Popup tukar barang: scan/cari barang pengganti, lalu selisihnya dibayar
/// pelanggan atau dikembalikan. Mengembalikan hasilnya, atau `null` bila
/// dibatalkan (belum ada yang tersimpan).
Future<ExchangeResult?> showExchangeDialog(
  BuildContext context,
  ExchangeRequest request,
) {
  return AppDialogs.popup<ExchangeResult>(
    context,
    title: 'Tukar Barang · ${request.invoiceNo}',
    maxWidth: 620,
    autofocusRoot: false,
    builder: (_) => _ExchangeForm(request: request),
  );
}

class _ExchangeForm extends ConsumerStatefulWidget {
  const _ExchangeForm({required this.request});

  final ExchangeRequest request;

  @override
  ConsumerState<_ExchangeForm> createState() => _ExchangeFormState();
}

class _ExchangeFormState extends ConsumerState<_ExchangeForm> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final _paid = TextEditingController();
  final _ref = TextEditingController();

  Cart _cart = const Cart();
  PaymentMethod? _method;

  /// Bayar terpisah: jumlah per metode (yang terisi = bagian pembayaran).
  bool _split = false;
  final _splitAmount = <int, TextEditingController>{};

  TextEditingController _amountOf(PaymentMethod m) =>
      _splitAmount.putIfAbsent(m.id, TextEditingController.new);
  String? _codeError;
  String? _error;
  bool _saving = false;

  ExchangeRequest get _req => widget.request;
  ExchangeTotals get _totals =>
      ExchangeTotals(credit: _req.credit, newTotal: _cart.total);
  bool get _isCash => _method?.isCash ?? true;

  @override
  void dispose() {
    _code.dispose();
    _codeFocus.dispose();
    _paid.dispose();
    _ref.dispose();
    for (final c in _splitAmount.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Harga mengikuti toko faktur asal.
  Future<ScanMatch?> _find(String code) =>
      ref.read(productRepositoryProvider).scan(code, storeId: _req.storeId);

  void _add(Product p, {ProductUnit? unit}) => setState(() {
    _cart = _cart.add(p, unit: unit);
    _codeError = null;
    _error = null;
    _code.clear();
  });

  Future<void> _submitCode([String? scanned]) async {
    final text = (scanned ?? _code.text).trim();
    if (text.isEmpty) return;
    final match = await _find(text);
    if (!mounted) return;
    if (match != null) {
      _add(match.product, unit: match.unit);
    } else {
      await _search(initial: text);
    }
    _codeFocus.requestFocus();
  }

  Future<void> _search({String initial = ''}) async {
    final picked = await showProductSearchSheet(context, initialQuery: initial);
    if (picked == null || !mounted) {
      if (initial.isNotEmpty && mounted) {
        setState(() => _codeError = 'Barang "$initial" tidak ditemukan.');
      }
      return;
    }
    final p = (await _find(picked.code))?.product ?? picked;
    if (mounted) _add(p);
  }

  Future<void> _saveSplit() async {
    final methods = ref.read(activePaymentMethodsProvider).value ?? const [];
    final parts = [
      for (final m in methods)
        if (parseIdNumber(_amountOf(m).text)?.round() case final a? when a > 0)
          PaymentPart(
            methodId: m.id,
            name: m.name,
            isCash: m.isCash,
            amount: a,
          ),
    ];
    if (parts.length < 2) {
      setState(() => _error = 'Isi jumlah minimal dua metode.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(exchangeServiceProvider)
          .exchange(
            actor: ref.read(authControllerProvider)!,
            saleId: _req.saleId,
            qtys: _req.qtys,
            reason: _req.reason,
            replacement: _cart,
            split: parts,
          );
      if (mounted) Navigator.pop(context, result);
    } on CheckoutFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ReturnFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (_split && _totals.customerPays > 0) return _saveSplit();
    final method = _method;
    if (_saving || method == null) return;
    final pays = _totals.customerPays;
    final paidText = parseIdNumber(_paid.text)?.round();
    // Tunai: kolom kosong = uang pas.
    final cash = method.isCash ? (paidText ?? pays) : null;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(exchangeServiceProvider)
          .exchange(
            actor: ref.read(authControllerProvider)!,
            saleId: _req.saleId,
            qtys: _req.qtys,
            reason: _req.reason,
            replacement: _cart,
            paymentMethodId: method.id,
            paid: cash,
            paymentRef: method.isCash ? null : _ref.text,
          );
      if (mounted) Navigator.pop(context, result);
    } on CheckoutFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on ReturnFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final methods = ref.watch(activePaymentMethodsProvider).value ?? const [];
    if (_method == null && methods.isNotEmpty) _method = methods.first;
    final t = _totals;
    final paidText = parseIdNumber(_paid.text)?.round();
    final change = _isCash && paidText != null && paidText > t.customerPays
        ? paidText - t.customerPays
        : 0;
    final muted = AppTypography.footnote.copyWith(color: c.labelSecondary);
    const tabular = [FontFeature.tabularFigures()];

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
          Text(
            '${_req.itemCount} barang dikembalikan senilai '
            '${Fmt.rupiah(_req.credit)} menjadi kredit. Scan atau cari '
            'barang penggantinya.',
            style: muted,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: WithScanButton(
                  onScanned: (code) => _submitCode(code),
                  field: AppTextField(
                    controller: _code,
                    focusNode: _codeFocus,
                    autofocus: true,
                    label: 'Barang pengganti',
                    placeholder: 'Scan / ketik barcode, lalu Enter',
                    prefixIcon: CupertinoIcons.barcode,
                    errorText: _codeError,
                    onChanged: (_) {
                      if (_codeError != null) {
                        setState(() => _codeError = null);
                      }
                    },
                    onSubmitted: (_) => _submitCode(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.only(top: 22),
                child: AppIconButton(
                  icon: CupertinoIcons.search,
                  tooltip: 'Cari barang',
                  size: 44,
                  filled: true,
                  onPressed: () => _search(),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            constraints: const BoxConstraints(minHeight: 56, maxHeight: 240),
            decoration: BoxDecoration(
              color: c.fillSecondary,
              borderRadius: AppRadius.mdAll,
            ),
            child: _cart.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Text('Belum ada barang pengganti', style: muted),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    itemCount: _cart.lines.length,
                    separatorBuilder: (_, _) =>
                        Container(height: 0.5, color: c.separator),
                    itemBuilder: (_, i) {
                      final l = _cart.lines[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.product.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTypography.subheadline.copyWith(
                                      color: c.label,
                                    ),
                                  ),
                                  Text(
                                    '${l.product.code} · '
                                    '${Fmt.rupiah(l.price)}'
                                    '${l.unitName == null ? '' : '/${l.unitName}'}',
                                    style: AppTypography.caption.copyWith(
                                      color: c.labelSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            AppIconButton(
                              icon: CupertinoIcons.minus,
                              tooltip: 'Kurangi',
                              size: 32,
                              onPressed: () => setState(
                                () => _cart = _cart.setQty(i, l.qty - 1),
                              ),
                            ),
                            SizedBox(
                              width: 36,
                              child: Text(
                                Fmt.number(l.qty),
                                textAlign: TextAlign.center,
                                style: AppTypography.subheadline.copyWith(
                                  color: c.label,
                                  fontFeatures: tabular,
                                ),
                              ),
                            ),
                            AppIconButton(
                              icon: CupertinoIcons.plus,
                              tooltip: 'Tambah',
                              size: 32,
                              onPressed: () => setState(
                                () => _cart = _cart.setQty(i, l.qty + 1),
                              ),
                            ),
                            SizedBox(
                              width: 84,
                              child: Text(
                                Fmt.rupiah(l.total),
                                textAlign: TextAlign.right,
                                style: AppTypography.subheadline.copyWith(
                                  color: c.label,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: tabular,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: c.fillSecondary,
              borderRadius: AppRadius.mdAll,
            ),
            child: Column(
              children: [
                _Line('Barang pengganti', Fmt.rupiah(t.newTotal)),
                _Line(
                  'Kredit barang dikembalikan',
                  '− ${Fmt.rupiah(t.credit)}',
                  color: c.success,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        t.refund > 0
                            ? 'Kembalikan ke pelanggan'
                            : t.customerPays > 0
                            ? 'Pelanggan bayar'
                            : 'Pas, tanpa selisih',
                        style: AppTypography.headline.copyWith(color: c.label),
                      ),
                    ),
                    Text(
                      Fmt.rupiah(t.refund > 0 ? t.refund : t.customerPays),
                      style: AppTypography.displayAmount.copyWith(
                        color: t.refund > 0 ? c.success : c.label,
                        fontSize: 30,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (methods.isEmpty)
            const ErrorBanner(message: 'Belum ada metode pembayaran aktif.')
          else if (_split && t.customerPays > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in methods)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: AppTextField(
                      controller: _amountOf(m),
                      label: m.isCash ? '${m.name} (uang diterima)' : m.name,
                      placeholder: '0',
                      keyboardType: TextInputType.number,
                      inputFormatters: [RupiahInputFormatter()],
                      onChanged: (_) => setState(() => _error = null),
                    ),
                  ),
              ],
            )
          else
            ChoiceChips<PaymentMethod>(
              values: methods,
              selected: _method ?? methods.first,
              label: (m) => m.name,
              onSelected: (m) => setState(() {
                _method = m;
                _error = null;
              }),
            ),
          if (t.customerPays > 0 && methods.length >= 2)
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: _split
                    ? 'Bayar dengan satu metode'
                    : 'Bayar terpisah (beberapa metode)',
                variant: AppButtonVariant.plain,
                size: AppButtonSize.small,
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _split = !_split;
                        _error = null;
                      }),
              ),
            ),
          if (t.customerPays > 0 && !_split) ...[
            const SizedBox(height: AppSpacing.sm),
            _isCash
                ? AppTextField(
                    controller: _paid,
                    label: 'Uang diterima',
                    placeholder: 'Kosong = uang pas',
                    keyboardType: TextInputType.number,
                    inputFormatters: [RupiahInputFormatter()],
                    helper: change > 0
                        ? 'Kembalian ${Fmt.rupiah(change)}'
                        : null,
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _save(),
                  )
                : AppTextField(
                    controller: _ref,
                    label: 'No. referensi (opsional)',
                  ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.lg),
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
                  label: 'Selesaikan Tukar',
                  icon: CupertinoIcons.arrow_2_squarepath,
                  expand: true,
                  loading: _saving,
                  onPressed: _cart.isEmpty || _method == null ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.color});

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
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
