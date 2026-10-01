import 'package:flutter/cupertino.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'app_card.dart';

/// Kartu angka ringkasan: label, nilai besar, dan opsional perubahan
/// dibanding periode sebelumnya (panah + teks, tidak hanya warna).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.caption,
    this.delta,
    this.deltaLabel,
    this.higherIsBetter = true,
    this.onPressed,
  });

  final String label;
  final String value;
  final IconData icon;

  /// Warna ikon penanda kartu (bukan warna teks).
  final Color color;
  final String? caption;

  /// Perubahan relatif (0,12 = naik 12%). `null` = tidak ditampilkan.
  final double? delta;

  /// Pembanding, mis. "vs kemarin".
  final String? deltaLabel;
  final bool higherIsBetter;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      onPressed: onPressed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.subheadline.copyWith(
                    color: c.labelSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: AppTypography.title1.copyWith(color: c.label),
            ),
          ),
          if (delta != null || caption != null) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                if (delta != null)
                  _Delta(delta: delta!, higherIsBetter: higherIsBetter),
                if (delta != null && (deltaLabel ?? caption) != null)
                  const SizedBox(width: 4),
                if ((deltaLabel ?? caption) != null)
                  Flexible(
                    child: Text(
                      delta != null ? (deltaLabel ?? '') : caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.footnote.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Delta extends StatelessWidget {
  const _Delta({required this.delta, required this.higherIsBetter});

  final double delta;
  final bool higherIsBetter;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final flat = delta.abs() < 0.0005;
    final up = delta > 0;
    final good = flat ? null : (up == higherIsBetter);
    final color = good == null
        ? c.labelSecondary
        : good
        ? c.success
        : c.danger;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          flat
              ? CupertinoIcons.minus
              : up
              ? CupertinoIcons.arrow_up_right
              : CupertinoIcons.arrow_down_right,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          Fmt.percent(delta.abs(), decimals: 0),
          style: AppTypography.footnote.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
