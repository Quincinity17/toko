import 'package:flutter/cupertino.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../domain/tag.dart';

/// Label tag berwarna penuh (mudah dikenali dari warnanya). [onRemove]
/// menampilkan tombol × (di form barang).
class TagChip extends StatelessWidget {
  const TagChip({
    super.key,
    required this.name,
    required this.color,
    this.small = false,
    this.onRemove,
  });

  TagChip.of(Tag tag, {Key? key, bool small = false, VoidCallback? onRemove})
    : this(
        key: key,
        name: tag.name,
        color: tag.color,
        small: small,
        onRemove: onRemove,
      );

  final String name;
  final TagColor color;
  final bool small;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final fill = color.color;
    final ink = color.onColor;
    final style = (small ? AppTypography.caption : AppTypography.footnote)
        .copyWith(color: ink, fontWeight: FontWeight.w600);
    return Container(
      padding: EdgeInsets.fromLTRB(
        small ? 7 : 10,
        small ? 2 : 4,
        onRemove == null ? (small ? 7 : 10) : 4,
        small ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(small ? 6 : 8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, style: style),
          if (onRemove != null)
            PressableScale(
              onPressed: onRemove,
              pressedScale: 0.85,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  CupertinoIcons.xmark_circle_fill,
                  size: 16,
                  color: ink.withValues(alpha: 0.75),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Deretan chip tag (dibungkus ke baris berikut bila tidak muat).
class TagChips extends StatelessWidget {
  const TagChips({super.key, required this.tags, this.small = true});

  final List<Tag> tags;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [for (final t in tags) TagChip.of(t, small: small)],
    );
  }
}
