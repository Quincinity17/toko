import 'package:flutter/cupertino.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/cart.dart';

/// Panel kanan layar kasir: total besar, lalu tombol Bayar dan Batalkan.
class CartSummaryPanel extends StatelessWidget {
  const CartSummaryPanel({
    super.key,
    required this.cart,
    required this.onPay,
    required this.onClear,
  });

  final Cart cart;
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
