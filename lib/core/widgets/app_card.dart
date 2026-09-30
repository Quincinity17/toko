import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'pressable_scale.dart';

/// Kartu putih membulat tanpa garis tepi, dengan bayangan sangat halus.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onPressed,
    this.color,
    this.radius = AppRadius.lgAll,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onPressed;
  final Color? color;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? c.card,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onPressed == null) return card;
    return PressableScale(
      onPressed: onPressed,
      pressedScale: 0.98,
      borderRadius: radius,
      child: card,
    );
  }
}

/// Panel kaca buram (frosted glass) untuk sidebar, toolbar, dan panel melayang.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.blur = 30,
    this.tint,
    this.opacity = 0.72,
    this.border,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final Color? tint;
  final double opacity;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final base = tint ?? context.colors.sidebar;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: base.withValues(alpha: opacity),
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        ),
      ),
    );
  }
}
