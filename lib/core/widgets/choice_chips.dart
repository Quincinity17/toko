import 'package:flutter/cupertino.dart';

import '../theme/app_theme.dart';
import 'pressable_scale.dart';

/// Deretan pilihan berbentuk kapsul (satu terpilih), bisa melipat ke baris
/// berikutnya di layar sempit.
class ChoiceChips<T> extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    this.icon,
    required this.onSelected,
    this.subtle = false,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final IconData? Function(T)? icon;
  final ValueChanged<T> onSelected;

  /// Gaya lebih tenang untuk navigasi bagian (bukan filter).
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final v in values)
          PressableScale(
            onPressed: () => onSelected(v),
            pressedScale: 0.95,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: AppDurations.fast,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: v == selected
                    ? (subtle ? c.accentTint : c.accent)
                    : c.fill,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon?.call(v) case final iconData?) ...[
                    Icon(
                      iconData,
                      size: 15,
                      color: v == selected
                          ? (subtle ? c.accent : CupertinoColors.white)
                          : c.labelSecondary,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label(v),
                    style: AppTypography.footnote.copyWith(
                      color: v == selected
                          ? (subtle ? c.accent : CupertinoColors.white)
                          : c.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
