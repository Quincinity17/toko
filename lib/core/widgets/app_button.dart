import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'pressable_scale.dart';

enum AppButtonVariant {
  /// Latar aksen penuh, untuk aksi utama (Bayar, Simpan).
  filled,

  /// Latar aksen transparan, untuk aksi sekunder.
  tinted,

  /// Latar abu-abu netral.
  gray,

  /// Hanya teks berwarna aksen.
  plain,
}

enum AppButtonSize { small, medium, large }

/// Tombol bergaya iOS. Ukuran [AppButtonSize.large] dipakai untuk aksi kasir
/// yang sering disentuh.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.filled,
    this.size = AppButtonSize.medium,
    this.destructive = false,
    this.expand = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool destructive;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = destructive ? c.danger : c.accent;

    final (Color bg, Color fg) = switch (variant) {
      AppButtonVariant.filled => (tone, CupertinoColors.white),
      AppButtonVariant.tinted => (tone.withValues(alpha: 0.14), tone),
      AppButtonVariant.gray => (c.fill, tone),
      AppButtonVariant.plain => (Colors.transparent, tone),
    };

    final (
      double height,
      double hPad,
      TextStyle text,
      double iconSize,
    ) = switch (size) {
      AppButtonSize.small => (36, 14, AppTypography.subheadline, 16),
      AppButtonSize.medium => (
        AppSizes.touchTarget,
        20,
        AppTypography.headline,
        20,
      ),
      AppButtonSize.large => (
        AppSizes.buttonLarge,
        28,
        AppTypography.title3,
        22,
      ),
    };

    final radius = size == AppButtonSize.small
        ? AppRadius.smAll
        : AppRadius.mdAll;

    Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          CupertinoActivityIndicator(color: fg, radius: iconSize / 2.4)
        else if (icon != null)
          Icon(icon, size: iconSize, color: fg),
        if ((loading || icon != null) && label.isNotEmpty)
          const SizedBox(width: AppSpacing.xs),
        if (label.isNotEmpty)
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: text.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );

    return PressableScale(
      onPressed: loading ? null : onPressed,
      borderRadius: radius,
      hoverColor: variant == AppButtonVariant.filled
          ? Colors.white.withValues(alpha: 0.12)
          : null,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: hPad),
        decoration: BoxDecoration(color: bg, borderRadius: radius),
        child: content,
      ),
    );
  }
}

/// Tombol ikon bulat kecil untuk toolbar.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 36,
    this.filled = false,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final bool filled;

  /// Warna ikon; bawaan aksen. Redup saat [onPressed] `null`.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = PressableScale(
      onPressed: onPressed,
      pressedScale: 0.9,
      borderRadius: BorderRadius.circular(size / 2),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: filled ? c.fill : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: size * 0.55,
          color: onPressed == null
              ? (color ?? c.accent).withValues(alpha: 0.35)
              : color ?? c.accent,
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
