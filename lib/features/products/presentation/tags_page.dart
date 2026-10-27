import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/color_wheel.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/tag_repository.dart';
import '../domain/code_prefix.dart';
import '../domain/tag.dart';
import 'tag_chip.dart';

/// Pengaturan › Kelola Kategori (khusus admin): kategori barang seperti Mainan,
/// Boneka, Alat Tulis. Satu barang bisa punya banyak kategori (di kode: tag).
class TagsPage extends ConsumerWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider);

    return LargeTitlePage(
      title: 'Kelola Kategori',
      backLabel: 'Pengaturan',
      onBack: () => context.go(AppRoutes.pengaturan),
      actions: [
        AppButton(
          label: 'Tambah Kategori',
          icon: CupertinoIcons.add,
          onPressed: () => showTagForm(context),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: tags.when(
            loading: () => const SizedBox(height: 240, child: LoadingState()),
            error: (e, _) => ErrorBanner(message: '$e'),
            data: (list) => Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: list.isEmpty
                    ? EmptyState(
                        icon: CupertinoIcons.tag,
                        title: 'Belum ada kategori',
                        message:
                            'Kategori mengelompokkan barang menurut jenisnya, mis. '
                            'Mainan, Boneka, Alat Tulis. Satu barang bisa '
                            'punya beberapa kategori.',
                        actionLabel: 'Tambah Kategori',
                        onAction: () => showTagForm(context),
                      )
                    : InsetGroupedSection(
                        footer:
                            'Kategori dipasang di form barang dan bisa dipakai '
                            'untuk memfilter daftar barang serta di laporan. '
                            'Menghapus kategori tidak menghapus barangnya.',
                        dividerIndent: 58,
                        children: [
                          for (final t in list)
                            InsetGroupedTile(
                              leading: TileIcon(
                                icon: CupertinoIcons.tag_fill,
                                color: t.color.color,
                              ),
                              title: t.name,
                              subtitle: t.codePrefix == null
                                  ? t.color.label
                                  : '${t.color.label} · barcode ${t.codePrefix}…',
                              value: '${t.productCount} barang',
                              onPressed: () =>
                                  showTagForm(context, existing: t),
                            ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Sheet tambah/ubah kategori: nama dan warna.
Future<void> showTagForm(BuildContext context, {Tag? existing}) {
  return AppDialogs.sheet<void>(
    context,
    title: existing == null ? 'Kategori Baru' : 'Ubah Kategori',
    builder: (_) => _TagForm(existing: existing),
  );
}

class _TagForm extends ConsumerStatefulWidget {
  const _TagForm({this.existing});

  final Tag? existing;

  @override
  ConsumerState<_TagForm> createState() => _TagFormState();
}

class _TagFormState extends ConsumerState<_TagForm> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _prefix = TextEditingController(text: widget.existing?.codePrefix);
  late final _digits = TextEditingController(
    text: widget.existing?.codeDigits?.toString(),
  );
  late TagColor _color = widget.existing?.color ?? TagColor.blue;
  String? _nameError;
  String? _prefixError;

  /// Saran awalan barcode dari nama kategori (dihitung ulang setelah jeda).
  List<String> _suggestions = const [];
  Timer? _suggestTimer;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  void _onNameChanged(String _) {
    setState(() {});
    _suggestTimer?.cancel();
    _suggestTimer = Timer(const Duration(milliseconds: 300), _loadSuggestions);
  }

  Future<void> _loadSuggestions() async {
    final name = _name.text.trim();
    final list = name.isEmpty
        ? const <String>[]
        : await ref
              .read(tagRepositoryProvider)
              .suggestPrefixes(name, tagId: widget.existing?.id);
    if (mounted) setState(() => _suggestions = list);
  }

  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _suggestTimer?.cancel();
    _name.dispose();
    _prefix.dispose();
    _digits.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = TagRules.name(_name.text);
    final digits = int.tryParse(_digits.text.trim());
    final prefixError =
        CodePrefix.validate(_prefix.text) ??
        (_digits.text.trim().isNotEmpty &&
                (digits == null || digits < 2 || digits > 10)
            ? 'Jumlah digit 2–10.'
            : null);
    setState(() {
      _nameError = error;
      _prefixError = prefixError;
      _error = null;
    });
    if (error != null || prefixError != null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(tagRepositoryProvider)
          .save(
            actor: ref.read(authControllerProvider)!,
            id: widget.existing?.id,
            name: _name.text,
            color: _color,
            codePrefix: _prefix.text,
            codeDigits: digits,
          );
      if (mounted) Navigator.pop(context);
    } on TagFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Warna bebas lewat color wheel / kode hex.
  Future<void> _pickCustom() async {
    final name = _name.text.trim().isEmpty ? 'Contoh' : _name.text.trim();
    final picked = await showColorWheelPicker(
      context,
      initial: _color.color,
      title: 'Warna Kategori',
      previewBuilder: (color) =>
          TagChip(name: name, color: TagColor.custom(color)),
    );
    if (picked != null && mounted) {
      setState(() => _color = TagColor.custom(picked));
    }
  }

  Future<void> _delete() async {
    final t = widget.existing!;
    final ok = await AppDialogs.confirm(
      context,
      title: 'Hapus kategori ${t.name}?',
      message: t.productCount == 0
          ? 'Kategori belum dipakai barang mana pun.'
          : 'Kategori dilepas dari ${t.productCount} barang. Barangnya tidak '
                'ikut terhapus.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref
          .read(tagRepositoryProvider)
          .remove(actor: ref.read(authControllerProvider)!, id: t.id);
      if (mounted) Navigator.pop(context);
    } on TagFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final preview = _name.text.trim().isEmpty ? 'Contoh' : _name.text.trim();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _name,
            label: 'Nama kategori',
            placeholder: 'mis. Mainan, Boneka, Alat Tulis',
            autofocus: widget.existing == null,
            errorText: _nameError,
            onChanged: _onNameChanged,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: AppTextField(
                  controller: _prefix,
                  label: 'Awalan barcode otomatis (opsional)',
                  placeholder: 'mis. BNK',
                  prefixIcon: CupertinoIcons.barcode,
                  errorText: _prefixError,
                  helper: switch (CodePrefix.normalize(_prefix.text)) {
                    final p? when CodePrefix.validate(p) == null =>
                      'Barcode otomatis barang baru di kategori ini diawali $p '
                          '(nomor terlewat diisi dulu).',
                    _ =>
                      'Kosong = mengikuti barcode barang yang sudah ada di '
                          'kategori ini.',
                  },
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9-]')),
                    LengthLimitingTextInputFormatter(CodePrefix.maxLength),
                  ],
                  onChanged: (_) => setState(() => _prefixError = null),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: AppTextField(
                  controller: _digits,
                  label: 'Jumlah digit',
                  placeholder: 'mis. 4',
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(2),
                  ],
                  helper: switch ((
                    CodePrefix.normalize(_prefix.text),
                    int.tryParse(_digits.text),
                  )) {
                    (final p?, final d?) when d >= 2 && d <= 10 =>
                      'Contoh: $p${'1'.padLeft(d, '0')}',
                    _ => 'Kosong = ikut seri yang ada.',
                  },
                  onChanged: (_) => setState(() => _prefixError = null),
                ),
              ),
            ],
          ),
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Saran:',
                  style: AppTypography.footnote.copyWith(
                    color: c.labelSecondary,
                  ),
                ),
                for (final p in _suggestions)
                  _PrefixChip(
                    label: p,
                    selected: CodePrefix.normalize(_prefix.text) == p,
                    onTap: () => setState(() {
                      _prefix.text = p;
                      _prefixError = null;
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Warna',
            style: AppTypography.footnote.copyWith(
              color: c.labelSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final color in TagColor.values)
                PressableScale(
                  onPressed: () => setState(() => _color = color),
                  pressedScale: 0.9,
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color == _color
                            ? c.label
                            : const Color(0x00000000),
                        width: 2.5,
                      ),
                    ),
                    child: color == _color
                        ? Icon(
                            CupertinoIcons.checkmark_alt,
                            size: 18,
                            color: color.onColor,
                          )
                        : null,
                  ),
                ),
              _CustomColorSwatch(
                selected: _color.isCustom ? _color : null,
                onTap: _pickCustom,
              ),
            ],
          ),
          if (_color.isCustom)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Warna kustom ${_color.hex}',
                style: AppTypography.footnote.copyWith(color: c.labelSecondary),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text(
                'Tampilan: ',
                style: AppTypography.footnote.copyWith(color: c.labelSecondary),
              ),
              TagChip(name: preview, color: _color),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: widget.existing == null ? 'Tambah Kategori' : 'Simpan',
            size: AppButtonSize.large,
            expand: true,
            loading: _saving,
            onPressed: _save,
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: 'Hapus Kategori',
              variant: AppButtonVariant.plain,
              destructive: true,
              expand: true,
              onPressed: _saving ? null : _delete,
            ),
          ],
        ],
      ),
    );
  }
}

/// Lingkaran pelangi "warna kustom"; berisi warna kustom bila terpilih.
class _CustomColorSwatch extends StatelessWidget {
  const _CustomColorSwatch({required this.selected, required this.onTap});

  final TagColor? selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sel = selected;
    return PressableScale(
      key: const ValueKey('custom-color'),
      onPressed: onTap,
      pressedScale: 0.9,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 32,
        height: 32,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [
              Color(0xFFFF3B30),
              Color(0xFFFFCC00),
              Color(0xFF34C759),
              Color(0xFF32ADE6),
              Color(0xFF5856D6),
              Color(0xFFFF2D55),
              Color(0xFFFF3B30),
            ],
          ),
          border: Border.all(
            color: sel != null ? c.label : const Color(0x00000000),
            width: 2.5,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: sel?.color ?? c.cardElevated,
            shape: BoxShape.circle,
          ),
          child: Icon(
            sel != null
                ? CupertinoIcons.checkmark_alt
                : CupertinoIcons.eyedropper,
            size: 14,
            color: sel?.onColor ?? c.labelSecondary,
          ),
        ),
      ),
    );
  }
}

/// Kapsul saran awalan barcode.
class _PrefixChip extends StatelessWidget {
  const _PrefixChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressableScale(
      onPressed: onTap,
      pressedScale: 0.94,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.accent : c.fill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: AppTypography.subheadline.copyWith(
            color: selected ? const Color(0xFFFFFFFF) : c.label,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
