import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import 'app_dialogs.dart';
import 'pressable_scale.dart';

/// Hasil [showOptionPicker]: opsi yang dipilih, atau [cleared] jika user
/// memilih "Tanpa …". `null` (bukan objek ini) berarti dibatalkan.
class OptionPick {
  const OptionPick(this.value);

  static const cleared = OptionPick(null);

  final String? value;
}

/// Popup memilih satu opsi dari daftar, dengan pencarian. Jika [allowCreate],
/// teks yang belum ada di daftar bisa langsung dipakai sebagai opsi baru
/// (mis. kategori atau satuan baru).
Future<OptionPick?> showOptionPicker(
  BuildContext context, {
  required String title,
  required List<String> options,
  String? selected,
  bool allowCreate = false,
  String? clearLabel,
}) {
  return AppDialogs.popup<OptionPick>(
    context,
    title: title,
    maxWidth: 420,
    autofocusRoot: false,
    builder: (_) => _OptionList(
      options: options,
      selected: selected,
      allowCreate: allowCreate,
      clearLabel: clearLabel,
    ),
  );
}

class _OptionList extends StatefulWidget {
  const _OptionList({
    required this.options,
    required this.selected,
    required this.allowCreate,
    required this.clearLabel,
  });

  final List<String> options;
  final String? selected;
  final bool allowCreate;
  final String? clearLabel;

  @override
  State<_OptionList> createState() => _OptionListState();
}

class _OptionListState extends State<_OptionList> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<String> get _filtered {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return widget.options.where((o) => o.toLowerCase().contains(q)).toList();
  }

  bool get _canCreate {
    final q = _query.text.trim();
    return widget.allowCreate &&
        q.isNotEmpty &&
        !widget.options.any((o) => o.toLowerCase() == q.toLowerCase());
  }

  void _submit() {
    final list = _filtered;
    if (_canCreate) {
      Navigator.pop(context, OptionPick(_query.text.trim()));
    } else if (list.isNotEmpty) {
      Navigator.pop(context, OptionPick(list.first));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final list = _filtered;
    final height = MediaQuery.sizeOf(context).height * 0.5;

    Widget row(
      String label,
      OptionPick result, {
      bool selected = false,
      IconData? icon,
      Color? color,
    }) => PressableScale(
      onPressed: () => Navigator.pop(context, result),
      pressedScale: 0.99,
      borderRadius: AppRadius.smAll,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? c.accentTint : Colors.transparent,
          borderRadius: AppRadius.smAll,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: color ?? c.accent),
              const SizedBox(width: AppSpacing.xs),
            ],
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(color: color ?? c.label),
              ),
            ),
            if (selected)
              Icon(CupertinoIcons.checkmark_alt, size: 18, color: c.accent),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): _submit,
            },
            child: CupertinoSearchTextField(
              controller: _query,
              autofocus: true,
              placeholder: widget.allowCreate ? 'Cari atau ketik baru' : 'Cari',
              style: AppTypography.body.copyWith(color: c.label),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height),
            child: ListView(
              shrinkWrap: true,
              children: [
                if (_canCreate)
                  row(
                    'Tambah "${_query.text.trim()}"',
                    OptionPick(_query.text.trim()),
                    icon: CupertinoIcons.add_circled_solid,
                    color: c.accent,
                  ),
                if (widget.clearLabel != null && _query.text.isEmpty)
                  row(
                    widget.clearLabel!,
                    OptionPick.cleared,
                    icon: CupertinoIcons.clear_circled,
                    color: c.labelSecondary,
                  ),
                for (final o in list)
                  row(o, OptionPick(o), selected: o == widget.selected),
                if (list.isEmpty && !_canCreate)
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'Tidak ada yang cocok.',
                      textAlign: TextAlign.center,
                      style: AppTypography.subheadline.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
