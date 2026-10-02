import 'package:flutter/cupertino.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../domain/cart.dart';

/// Panel kanan layar kasir: total besar, lalu tombol Tahan/Tertahan, Bayar,
/// dan Batalkan.
class CartSummaryPanel extends StatelessWidget {
  const CartSummaryPanel({
    super.key,
    required this.cart,
    required this.heldCount,
    required this.onPay,
    required this.onHold,
    required this.onShowHeld,
    required this.onClear,
    this.onOpenDrawer,
  });

  final Cart cart;

  /// Jumlah transaksi tertahan hari ini.
  final int heldCount;
  final VoidCallback onPay;
  final VoidCallback onHold;
  final VoidCallback onShowHeld;
  final VoidCallback onClear;

  /// Buka laci uang tanpa transaksi; `null` = printer belum diatur.
  final VoidCallback? onOpenDrawer;

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
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: 'Tahan  (F4)',
                variant: AppButtonVariant.tinted,
                expand: true,
                onPressed: cart.isEmpty ? null : onHold,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              // Jumlah tertahan sebagai lencana agar label tidak terpotong.
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AppButton(
                    label: 'Tertahan  (F5)',
                    variant: AppButtonVariant.tinted,
                    expand: true,
                    onPressed: heldCount == 0 ? null : onShowHeld,
                  ),
                  if (heldCount > 0)
                    Positioned(
                      top: -6,
                      right: -4,
                      child: IgnorePointer(
                        child: Container(
                          key: const ValueKey('held-count'),
                          constraints: const BoxConstraints(minWidth: 22),
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.danger,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            '$heldCount',
                            style: AppTypography.caption.copyWith(
                              color: CupertinoColors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
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
        if (onOpenDrawer != null) ...[
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            label: 'Buka Laci  (F6)',
            icon: CupertinoIcons.tray_arrow_down,
            variant: AppButtonVariant.plain,
            expand: true,
            onPressed: onOpenDrawer,
          ),
        ],
      ],
    );
  }
}
