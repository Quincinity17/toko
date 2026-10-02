import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/tag_repository.dart';
import '../domain/tag.dart';

/// Popup memilih beberapa tag untuk satu barang, dengan pencarian dan
/// pembuatan tag baru. Mengembalikan nama tag terpilih, atau `null` bila
/// dibatalkan.
Future<List<String>?> showTagPicker(
  BuildContext context, {
  required List<String> selected,
}) {
  return AppDialogs.popup<List<String>>(
    context,
    title: 'Tag Barang',
    maxWidth: 440,
    autofocusRoot: false,
    builder: (_) => _TagPicker(selected: selected),
  );
}

class _TagPicker extends ConsumerStatefulWidget {
  const _TagPicker({required this.selected});

  final List<String> selected;

  @override
  ConsumerState<_TagPicker> createState() => _TagPickerState();
}

class _TagPickerState extends ConsumerState<_TagPicker> {
  final _query = TextEditingController();

  /// Kunci huruf kecil → nama asli, urutan sesuai dipilih.
  late final Map<String, String> _picked = {
    for (final n in widget.selected) n.toLowerCase(): n,
  };
  String? _error;
  bool _creating = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _toggle(String name) => setState(() {
    final key = name.toLowerCase();
    if (_picked.remove(key) == null) _picked[key] = name;
  });

  Future<void> _create(String name, int existingCount) async {
    final error = TagRules.name(name);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      // Warna bergiliran supaya tag baru mudah dibedakan.
      final tag = await ref
          .read(tagRepositoryProvider)
          .save(
            actor: ref.read(authControllerProvider)!,
            name: name,
            color: TagColor.values[existingCount % TagColor.values.length],
          );
      _query.clear();
      _toggle(tag.name);
    } on TagFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tags = ref.watch(tagsProvider);
    final q = _query.text.trim();

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
          CupertinoSearchTextField(
            controller: _query,
            autofocus: true,
            placeholder: 'Cari atau buat tag baru',
            style: AppTypography.body.copyWith(color: c.label),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) {
              final list = tags.value ?? const <Tag>[];
              final exact = list
                  .where((t) => t.name.toLowerCase() == q.toLowerCase())
                  .firstOrNull;
              if (exact != null) {
                _toggle(exact.name);
                _query.clear();
              } else if (q.isNotEmpty) {
                _create(q, list.length);
              }
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 340),
            child: tags.when(
              loading: () => const SizedBox(height: 120, child: LoadingState()),
              error: (e, _) => ErrorBanner(message: '$e'),
              data: (list) {
                final shown = [
                  for (final t in list)
                    if (q.isEmpty ||
                        t.name.toLowerCase().contains(q.toLowerCase()))
                      t,
                ];
                final canCreate =
                    q.isNotEmpty &&
                    !list.any((t) => t.name.toLowerCase() == q.toLowerCase());
                return ListView(
                  shrinkWrap: true,
                  children: [
                    if (canCreate)
                      _Row(
                        leading: Icon(
                          CupertinoIcons.add_circled_solid,
                          size: 20,
                          color: c.accent,
                        ),
                        label: 'Buat tag "$q"',
                        labelColor: c.accent,
                        onTap: _creating ? null : () => _create(q, list.length),
                      ),
                    for (final t in shown)
                      _Row(
                        leading: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: t.color.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        label: t.name,
                        detail: '${t.productCount} barang',
                        checked: _picked.containsKey(t.name.toLowerCase()),
                        onTap: () => _toggle(t.name),
                      ),
                    if (list.isEmpty && !canCreate)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          'Belum ada tag. Ketik nama tag (mis. Mainan) lalu '
                          'Enter untuk membuatnya.',
                          textAlign: TextAlign.center,
                          style: AppTypography.subheadline.copyWith(
                            color: c.labelSecondary,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.md),
          AppButton(
            label: _picked.isEmpty
                ? 'Selesai (tanpa tag)'
                : 'Selesai (${_picked.length} tag)',
            expand: true,
            onPressed: () => Navigator.pop(context, _picked.values.toList()),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.label,
    this.labelColor,
    this.detail,
    this.checked = false,
    this.onTap,
  });

  final Widget leading;
  final String label;
  final Color? labelColor;
  final String? detail;
  final bool checked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressableScale(
      onPressed: onTap,
      pressedScale: 0.98,
      borderRadius: AppRadius.smAll,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: checked ? c.accentTint : null,
          borderRadius: AppRadius.smAll,
        ),
        child: Row(
          children: [
            SizedBox(width: 20, child: Center(child: leading)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(
                  color: labelColor ?? c.label,
                ),
              ),
            ),
            if (detail != null)
              Text(
                detail!,
                style: AppTypography.footnote.copyWith(color: c.labelSecondary),
              ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 20,
              child: checked
                  ? Icon(
                      CupertinoIcons.checkmark_alt,
                      size: 18,
                      color: c.accent,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
