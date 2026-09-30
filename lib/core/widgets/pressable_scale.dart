import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Pembungkus interaksi dasar: mengecil sedikit saat ditekan, highlight lembut
/// saat hover, dan kursor tangan di desktop. Dipakai oleh tombol, kartu, dan
/// baris list agar umpan baliknya konsisten.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onPressed,
    this.onLongPress,
    this.pressedScale = 0.97,
    this.borderRadius = AppRadius.mdAll,
    this.showHover = true,
    this.hoverColor,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final BorderRadius borderRadius;
  final bool showHover;
  final Color? hoverColor;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;
  bool _hovered = false;

  bool get _enabled => widget.onPressed != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hover = _enabled && widget.showHover && _hovered;

    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        onTapUp: _enabled ? (_) => _setPressed(false) : null,
        onTap: widget.onPressed == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onPressed!();
              },
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1,
          duration: _pressed ? AppDurations.fast : AppDurations.medium,
          curve: _pressed ? Curves.easeOut : SpringCurve.bouncy,
          child: AnimatedContainer(
            duration: AppDurations.fast,
            foregroundDecoration: BoxDecoration(
              color: hover
                  ? (widget.hoverColor ?? c.hover)
                  : (widget.hoverColor ?? c.hover).withValues(alpha: 0),
              borderRadius: widget.borderRadius,
            ),
            child: AnimatedOpacity(
              opacity: _enabled ? 1 : 0.4,
              duration: AppDurations.fast,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
