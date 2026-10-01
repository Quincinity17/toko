import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/cart.dart';

/// Panel kanan layar kasir: total besar, rincian, voucher, lalu tombol Bayar.
class CartSummaryPanel extends StatelessWidget {
  const CartSummaryPanel({
    super.key,
    required this.cart,
    required this.onApplyVoucher,
    required this.onRemoveVoucher,
    required this.onPay,
    required this.onClear,
  });

  final Cart cart;
  final VoidCallback onApplyVoucher;
  final VoidCallback onRemoveVoucher;
  final VoidCallback onPay;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

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
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      cart.isEmpty
                          ? 'Keranjang kosong'
                          : '${cart.lines.length} barang · '
                                '${Fmt.number(cart.totalQty)} item',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.footnote.copyWith(
                        color: c.labelSecondary,
                      ),
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Line(label: 'Subtotal', value: Fmt.rupiah(cart.subtotal)),
              const SizedBox(height: AppSpacing.sm),
              _VoucherBox(
                cart: cart,
                onApply: onApplyVoucher,
                onRemove: onRemoveVoucher,
              ),
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
          onPressed: cart.isEmpty ? null : onPay,
        ),
        const SizedBox(height: AppSpacing.xs),
        AppButton(
          label: 'Batalkan Transaksi',
          icon: CupertinoIcons.trash,
          variant: AppButtonVariant.gray,
          destructive: true,
          expand: true,
          onPressed: cart.isEmpty ? null : onClear,
        ),
      ],
    );
  }
}

/// Tombol "Pakai Voucher", atau kartu voucher terpasang beserta potongannya.
class _VoucherBox extends StatelessWidget {
  const _VoucherBox({
    required this.cart,
    required this.onApply,
    required this.onRemove,
  });

  final Cart cart;
  final VoidCallback onApply;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = cart.voucher;

    if (v == null) {
      return AppButton(
        label: 'Pakai Voucher  (F4)',
        icon: CupertinoIcons.tag,
        variant: AppButtonVariant.tinted,
        size: AppButtonSize.small,
        expand: true,
        onPressed: cart.isEmpty ? null : onApply,
      );
    }

    final short = cart.voucherShortfall;
    final ok = short == 0;
    return AnimatedContainer(
      duration: AppDurations.fast,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: (ok ? c.success : c.warning).withValues(alpha: 0.12),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          Icon(
            CupertinoIcons.tag_fill,
            size: 18,
            color: ok ? c.success : c.warning,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.code,
                  style: AppTypography.subheadline.copyWith(
                    color: c.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  ok
                      ? (v.name.isEmpty ? v.summary : v.name)
                      : 'Tambah belanja ${Fmt.rupiah(short)} lagi '
                            'agar voucher berlaku',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: ok ? c.labelSecondary : c.warning,
                  ),
                ),
              ],
            ),
          ),
          if (ok)
            Text(
              '− ${Fmt.rupiah(cart.discount)}',
              style: AppTypography.subheadline.copyWith(
                color: c.success,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          Tooltip(
            message: 'Lepas voucher',
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(36, 36),
              onPressed: onRemove,
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 20,
                color: c.labelTertiary,
              ),
            ),
          ),
        ],
      ),
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
