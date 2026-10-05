import 'package:flutter/cupertino.dart';

import '../../../../core/utils/device.dart';
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
    this.compact = false,
  });

  final Cart cart;

  /// HP: satu kartu di bawah (total + Bayar, tombol lain berupa ikon).
  final bool compact;

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
    if (compact) return _compact(c);

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
                label: Device.withShortcut('Tahan', 'F4'),
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
                    label: Device.withShortcut('Tertahan', 'F5'),
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
          label: Device.withShortcut('Bayar', 'F2'),
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
            label: Device.withShortcut('Buka Laci', 'F6'),
            icon: CupertinoIcons.tray_arrow_down,
            variant: AppButtonVariant.plain,
            expand: true,
            onPressed: onOpenDrawer,
          ),
        ],
      ],
    );
  }

  Widget _compact(AppColors c) {
    Widget icon(
      IconData icon,
      String tooltip,
      VoidCallback? onPressed, {
      bool danger = false,
      int badge = 0,
    }) => Stack(
      clipBehavior: Clip.none,
      children: [
        AppIconButton(
          icon: icon,
          tooltip: tooltip,
          filled: true,
          color: danger ? c.danger : null,
          onPressed: onPressed,
        ),
        if (badge > 0)
          Positioned(
            top: -4,
            right: -4,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('held-count'),
                constraints: const BoxConstraints(minWidth: 18),
                height: 18,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.danger,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '$badge',
                  style: AppTypography.caption.copyWith(
                    color: CupertinoColors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  cart.isEmpty
                      ? 'Keranjang kosong'
                      : '${cart.lines.length} barang · '
                            '${Fmt.number(cart.totalQty)} item',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.footnote.copyWith(
                    color: c.labelSecondary,
                  ),
                ),
              ),
              Flexible(
                flex: 2,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    Fmt.rupiah(cart.total),
                    style: AppTypography.displayAmount.copyWith(
                      color: c.label,
                      fontSize: 30,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              icon(
                CupertinoIcons.pause_circle,
                'Tahan transaksi',
                cart.isEmpty ? null : onHold,
              ),
              const SizedBox(width: AppSpacing.xs),
              icon(
                CupertinoIcons.tray_full,
                'Transaksi tertahan',
                heldCount == 0 ? null : onShowHeld,
                badge: heldCount,
              ),
              const SizedBox(width: AppSpacing.xs),
              icon(
                CupertinoIcons.trash,
                'Batalkan transaksi',
                cart.isEmpty ? null : onClear,
                danger: true,
              ),
              if (onOpenDrawer != null) ...[
                const SizedBox(width: AppSpacing.xs),
                icon(CupertinoIcons.tray_arrow_down, 'Buka laci', onOpenDrawer),
              ],
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Bayar',
                  icon: CupertinoIcons.creditcard_fill,
                  size: AppButtonSize.large,
                  expand: true,
                  onPressed: cart.isEmpty ? null : onPay,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
