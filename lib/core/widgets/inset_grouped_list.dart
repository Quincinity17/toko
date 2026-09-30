import 'package:flutter/cupertino.dart';

import '../theme/app_theme.dart';
import 'pressable_scale.dart';

/// Grup list bergaya aplikasi Pengaturan iOS: judul kecil di atas, baris-baris
/// dalam satu kartu membulat dengan pemisah tipis yang menjorok, dan catatan
/// kaki opsional.
class InsetGroupedSection extends StatelessWidget {
  const InsetGroupedSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.dividerIndent = AppSpacing.md,
  });

  final List<Widget> children;
  final String? header;
  final String? footer;

  /// Jarak kiri garis pemisah. Isi lebih besar jika baris punya ikon di kiri.
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(
          Padding(
            padding: EdgeInsets.only(left: dividerIndent),
            child: Container(height: 0.5, color: c.separator),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              header!.toUpperCase(),
              style: AppTypography.footnote.copyWith(
                color: c.labelSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ClipRRect(
          borderRadius: AppRadius.mdAll,
          child: ColoredBox(
            color: c.card,
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              0,
            ),
            child: Text(
              footer!,
              style: AppTypography.footnote.copyWith(color: c.labelSecondary),
            ),
          ),
      ],
    );
  }
}

/// Satu baris dalam [InsetGroupedSection].
class InsetGroupedTile extends StatelessWidget {
  const InsetGroupedTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.value,
    this.onPressed,
    this.showChevron,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;

  /// Biasanya [TileIcon].
  final Widget? leading;
  final Widget? trailing;

  /// Teks abu-abu di kanan, misalnya nilai pengaturan atau harga.
  final String? value;
  final VoidCallback? onPressed;

  /// Default: tampil jika [onPressed] diisi dan [trailing] kosong.
  final bool? showChevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chevron = showChevron ?? (onPressed != null && trailing == null);

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSizes.touchTarget + 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(
                      color: destructive ? c.danger : c.label,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.subheadline.copyWith(
                          color: c.labelSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: Text(
                  value!,
                  style: AppTypography.body.copyWith(color: c.labelSecondary),
                ),
              ),
            if (trailing != null)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: trailing!,
              ),
            if (chevron)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 16,
                  color: c.labelTertiary,
                ),
              ),
          ],
        ),
      ),
    );

    if (onPressed == null) return row;
    return PressableScale(
      onPressed: onPressed,
      pressedScale: 1,
      borderRadius: BorderRadius.zero,
      child: row,
    );
  }
}

/// Ikon kotak berwarna di kiri baris, seperti di Pengaturan iOS.
class TileIcon extends StatelessWidget {
  const TileIcon({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 18, color: CupertinoColors.white),
    );
  }
}
