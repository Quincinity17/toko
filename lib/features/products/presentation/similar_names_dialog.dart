import 'package:flutter/cupertino.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../domain/similar_names.dart';

/// Peringatan nama sama / mirip sebelum menyimpan barang baru. `true` =
/// Tetap Simpan. [showRow]: tampilkan nomor baris (Input Tabel).
Future<bool> showSimilarNamesConfirm(
  BuildContext context,
  List<SimilarName> found, {
  bool showRow = false,
}) async {
  final ok = await AppDialogs.popup<bool>(
    context,
    title: found.any((f) => f.exact) ? 'Nama sudah ada' : 'Nama mirip',
    maxWidth: 560,
    builder: (ctx) => _SimilarView(found: found, showRow: showRow),
  );
  return ok ?? false;
}

class _SimilarView extends StatelessWidget {
  const _SimilarView({required this.found, required this.showRow});

  final List<SimilarName> found;
  final bool showRow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = AppTypography.subheadline.copyWith(color: c.labelSecondary);
    final strong = AppTypography.subheadline.copyWith(
      color: c.label,
      fontWeight: FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Mungkin barang yang sama sudah tercatat. Periksa supaya tidak '
            'dobel; barang berbeda yang namanya mirip (mis. beda ukuran) '
            'tetap boleh disimpan.',
            style: muted,
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              color: c.fillSecondary,
              borderRadius: AppRadius.mdAll,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              itemCount: found.length,
              separatorBuilder: (_, _) =>
                  Container(height: 0.5, color: c.separator),
              itemBuilder: (_, i) {
                final f = found[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        f.exact
                            ? CupertinoIcons.exclamationmark_triangle_fill
                            : CupertinoIcons.info_circle_fill,
                        size: 18,
                        color: f.exact ? c.warning : c.labelSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (showRow) TextSpan(text: 'Baris ${f.key}: '),
                              TextSpan(text: f.name, style: strong),
                              TextSpan(
                                text: f.exact
                                    ? '  sama dengan  '
                                    : '  mirip dengan  ',
                              ),
                              TextSpan(text: f.matchLabel, style: strong),
                            ],
                          ),
                          style: muted,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Periksa Lagi',
                  variant: AppButtonVariant.gray,
                  expand: true,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Tetap Simpan',
                  icon: CupertinoIcons.checkmark_alt,
                  expand: true,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
