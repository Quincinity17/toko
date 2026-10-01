import 'package:flutter/cupertino.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/number_input.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/cart.dart';

/// Panel kanan layar kasir: total besar, rincian dan potongan transaksi,
/// lalu tombol Bayar. Beri `key` baru setiap transaksi baru agar isian
/// potongan ikut kosong.
class CartSummaryPanel extends StatefulWidget {
  const CartSummaryPanel({
    super.key,
    required this.cart,
    required this.onDiscountChanged,
    required this.onPay,
    required this.onClear,
  });

  final Cart cart;
  final void Function(DiscountType type, double value) onDiscountChanged;
  final VoidCallback onPay;
  final VoidCallback onClear;

  @override
  State<CartSummaryPanel> createState() => _CartSummaryPanelState();
}

class _CartSummaryPanelState extends State<CartSummaryPanel> {
  final _discount = TextEditingController();

  @override
  void dispose() {
    _discount.dispose();
    super.dispose();
  }

  void _changeType(DiscountType type) {
    _discount.clear();
    widget.onDiscountChanged(type, 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cart = widget.cart;
    final num = const [FontFeature.tabularFigures()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Total besar seperti layar iPOS.
        AppCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Text(
                    'TOTAL',
                    style: AppTypography.footnote.copyWith(
                      color: c.labelSecondary,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    cart.isEmpty
                        ? 'Keranjang kosong'
                        : '${cart.lines.length} barang · '
                              '${Fmt.number(cart.totalQty)} item',
                    style: AppTypography.footnote.copyWith(
                      color: c.labelSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: AnimatedSwitcher(
                  duration: AppDurations.medium,
                  switchInCurve: SpringCurve.bouncy,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: ScaleTransition(
                      scale: Tween(begin: 0.92, end: 1.0).animate(a),
                      alignment: Alignment.centerRight,
                      child: child,
                    ),
                  ),
                  child: Text(
                    Fmt.rupiah(cart.total),
                    key: ValueKey(cart.total),
                    style: AppTypography.displayAmount.copyWith(
                      color: c.label,
                      fontSize: 44,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            children: [
              _Line(label: 'Subtotal', value: Fmt.rupiah(cart.subtotal)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Potongan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.subheadline.copyWith(color: c.label),
                    ),
                  ),
                  CupertinoSlidingSegmentedControl<DiscountType>(
                    groupValue: cart.discountType,
                    padding: const EdgeInsets.all(2),
                    onValueChanged: (t) {
                      if (t != null && t != cart.discountType) _changeType(t);
                    },
                    children: const {
                      DiscountType.percent: _Seg('%'),
                      DiscountType.amount: _Seg('Rp'),
                    },
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  SizedBox(
                    width: 96,
                    child: CupertinoTextField(
                      controller: _discount,
                      placeholder: '0',
                      textAlign: TextAlign.right,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        if (cart.discountType == DiscountType.amount)
                          RupiahInputFormatter(),
                      ],
                      style: AppTypography.subheadline.copyWith(
                        color: c.label,
                        fontFeatures: num,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: c.fill,
                        borderRadius: AppRadius.smAll,
                      ),
                      onChanged: (v) => widget.onDiscountChanged(
                        cart.discountType,
                        parseIdNumber(v) ?? 0,
                      ),
                    ),
                  ),
                ],
              ),
              if (cart.discount > 0) ...[
                const SizedBox(height: AppSpacing.xxs),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '− ${Fmt.rupiah(cart.discount)}',
                    style: AppTypography.subheadline.copyWith(
                      color: c.danger,
                      fontFeatures: num,
                    ),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Container(height: 0.5, color: c.separator),
              ),
              _Line(label: 'Total', value: Fmt.rupiah(cart.total), bold: true),
            ],
          ),
        ),
        const Spacer(),
        AppButton(
          label: 'Bayar  (F2)',
          icon: CupertinoIcons.creditcard_fill,
          size: AppButtonSize.large,
          expand: true,
          onPressed: cart.isEmpty ? null : widget.onPay,
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          label: 'Batalkan Transaksi',
          icon: CupertinoIcons.trash,
          variant: AppButtonVariant.gray,
          destructive: true,
          expand: true,
          onPressed: cart.isEmpty ? null : widget.onClear,
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = (bold ? AppTypography.headline : AppTypography.subheadline)
        .copyWith(
          color: c.label,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
    return Row(
      children: [
        Text(label, style: style),
        const Spacer(),
        Text(value, style: style),
      ],
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    child: Text(label, style: AppTypography.footnote),
  );
}
