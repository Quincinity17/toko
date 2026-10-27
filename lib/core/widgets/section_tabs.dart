import 'package:flutter/cupertino.dart';

import '../theme/app_theme.dart';
import 'pressable_scale.dart';

/// Navigasi bagian berupa tab teks bergaris bawah (bukan kapsul), supaya
/// terbedakan dari chip filter di atasnya. Melipat ke baris berikutnya bila
/// tidak muat (tanpa geser samping, nyaman dipakai dengan mouse).
class SectionTabs<T> extends StatelessWidget {
  const SectionTabs({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.separator, width: 0.5)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          spacing: AppSpacing.lg,
          children: [
            for (final v in values)
              PressableScale(
                onPressed: () => onSelected(v),
                pressedScale: 0.97,
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: v == selected
                            ? c.accent
                            : const Color(0x00000000),
                        width: 2,
                      ),
                    ),
                  ),
                  child: Text(
                    label(v),
                    style: AppTypography.subheadline.copyWith(
                      color: v == selected ? c.accent : c.labelSecondary,
                      fontWeight: v == selected
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
