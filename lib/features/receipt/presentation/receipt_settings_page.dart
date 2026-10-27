import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/option_picker.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../stores/data/store_repository.dart';
import '../../stores/domain/store.dart';
import '../../stores/presentation/store_scope.dart';
import '../data/logo_image.dart';
import '../data/printer_failure.dart';
import '../data/receipt_renderer.dart';
import '../data/receipt_settings_repository.dart';
import '../domain/default_receipt_html.dart';
import '../domain/printer_config.dart';
import '../domain/receipt.dart';
import '../domain/receipt_html.dart';
import '../domain/receipt_template.dart';
import 'printer_settings_section.dart';

/// Memilih file logo; di-override di tes. Mengembalikan (byte, nama file).
final pickLogoFileProvider = Provider<Future<(Uint8List, String)?> Function()>(
  (ref) => () async {
    final file = await FilePicker.pickFile(
      dialogTitle: 'Pilih logo',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
    );
    if (file == null) return null;
    return (await file.readAsBytes(), file.name);
  },
);

/// Pengaturan › Struk & Printer (khusus admin): bentuk struk tiap toko
/// (template HTML + CSS + logo, dengan pratinjau langsung) dan printer
/// komputer ini. Setiap perubahan langsung disimpan.
class ReceiptSettingsPage extends ConsumerStatefulWidget {
  const ReceiptSettingsPage({super.key});

  @override
  ConsumerState<ReceiptSettingsPage> createState() =>
      _ReceiptSettingsPageState();
}

class _ReceiptSettingsPageState extends ConsumerState<ReceiptSettingsPage> {
  /// Toko yang bentuk struknya sedang diubah.
  int? _storeId;
  ReceiptTemplate? _template;

  final _editor = TextEditingController();
  final _editorFocus = FocusNode();

  /// Template ditulis → pratinjau & simpan ditunda sebentar.
  Timer? _debounce;

  /// HTML pratinjau terakhir yang berhasil diproses.
  String? _previewHtml;
  String? _templateError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickInitialStore());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _editor.dispose();
    _editorFocus.dispose();
    super.dispose();
  }

  List<Store> get _stores => ref.read(storesProvider).value ?? const [];

  Store? get _store {
    for (final s in _stores) {
      if (s.id == _storeId) return s;
    }
    return null;
  }

  /// Toko awal: toko yang dipilih di sidebar, atau toko aktif pertama.
  void _pickInitialStore() {
    if (!mounted || _storeId != null) return;
    final active = ref.read(activeStoreProvider);
    final stores = _stores;
    final id =
        active?.id ??
        stores.where((s) => s.isActive).firstOrNull?.id ??
        stores.firstOrNull?.id;
    if (id != null) _loadStore(id);
  }

  Future<void> _loadStore(int id) async {
    await _flushPending();
    final t = await ref.read(receiptSettingsRepositoryProvider).templateFor(id);
    if (!mounted) return;
    _editor.text = t.html;
    setState(() {
      _storeId = id;
      _template = t;
    });
    _refreshPreview();
  }

  /// Menulis bagian retur / bayar terpisah yang belum ada ke template
  /// supaya admin bisa mengatur letak & gayanya sendiri.
  void _addMissingSections() {
    final full = ReceiptSections.withFallbacks(_editor.text);
    _editor.text = full;
    _onEditorChanged(full);
  }

  // ── Simpan ──

  /// Simpan ketikan yang masih menunggu jeda (mis. sebelum pindah toko).
  Future<void> _flushPending() async {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      final t = _template;
      if (t != null && t.html != _editor.text) {
        await _setTemplate(t.copyWith(html: _editor.text));
      }
    }
  }

  Future<void> _setTemplate(ReceiptTemplate t) async {
    setState(() => _template = t);
    _refreshPreview();
    try {
      await ref
          .read(receiptSettingsRepositoryProvider)
          .saveTemplate(
            ref.read(authControllerProvider)!,
            t,
            storeId: _storeId!,
          );
    } on PrinterFailure catch (e) {
      if (mounted) {
        await AppDialogs.alert(context, title: 'Gagal', message: e.message);
      }
    }
  }

  void _onEditorChanged(String html) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _setTemplate(_template!.copyWith(html: html));
    });
  }

  // ── Pratinjau ──

  void _refreshPreview() {
    final t = _template;
    if (t == null) return;
    final store = _store;
    try {
      final html = ReceiptHtml.render(
        t.html,
        ReceiptData.sample(
          storeName: store?.name,
          storeAddress: store?.address,
        ).toTemplateValues(logo: t.logo),
      );
      setState(() {
        _previewHtml = html;
        _templateError = null;
      });
    } on ReceiptTemplateError catch (e) {
      // Pratinjau terakhir yang benar tetap tampil.
      setState(() => _templateError = e.message);
    }
  }

  // ── Template ──

  Future<void> _chooseStore() async {
    final stores = _stores;
    final pick = await showOptionPicker(
      context,
      title: 'Bentuk Struk Toko',
      options: [for (final s in stores) s.name],
      selected: _store?.name,
    );
    final name = pick?.value;
    if (name == null) return;
    final id = stores.firstWhere((s) => s.name == name).id;
    if (id != _storeId) await _loadStore(id);
  }

  Future<void> _applyToAll() async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'Terapkan template ke semua toko?',
      message:
          'Template HTML ${_store?.name ?? 'ini'} akan dipakai juga oleh semua '
          'toko lain. Logo tiap toko tidak berubah.',
      confirmLabel: 'Terapkan',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _flushPending();
    try {
      await ref
          .read(receiptSettingsRepositoryProvider)
          .applyHtmlToAllStores(
            ref.read(authControllerProvider)!,
            _editor.text,
          );
    } on PrinterFailure catch (e) {
      if (mounted) {
        await AppDialogs.alert(context, title: 'Gagal', message: e.message);
      }
    }
  }

  void _insertVariable(String text) {
    final value = _editor.value;
    final sel = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    final next = value.text.replaceRange(sel.start, sel.end, text);
    _editor.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: sel.start + text.length),
    );
    _editorFocus.requestFocus();
    _onEditorChanged(next);
  }

  Future<void> _resetTemplate() async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'Kembalikan template bawaan?',
      message:
          'Template HTML ${_store?.name ?? 'toko ini'} akan diganti template '
          'bawaan. Logo dan pengaturan printer tidak berubah.',
      confirmLabel: 'Kembalikan',
      destructive: true,
    );
    if (!ok) return;
    _debounce?.cancel();
    _editor.text = defaultReceiptHtml;
    await _setTemplate(_template!.copyWith(html: defaultReceiptHtml));
  }

  Future<void> _pickLogo() async {
    final picked = await ref.read(pickLogoFileProvider)();
    if (picked == null || !mounted) return;
    final String logo;
    try {
      logo = await logoToDataUri(picked.$1);
    } on PrinterFailure catch (e) {
      if (mounted) {
        await AppDialogs.alert(context, title: 'Logo', message: e.message);
      }
      return;
    }
    await _setTemplate(_template!.copyWith(logo: () => logo));
  }

  @override
  Widget build(BuildContext context) {
    // Daftar toko baru termuat → pilih toko awal; nama/alamat berubah →
    // pratinjau diperbarui.
    ref.listen(storesProvider, (_, _) {
      if (_storeId == null) {
        _pickInitialStore();
      } else {
        _refreshPreview();
      }
    });
    final paperWidth =
        ref.watch(printerConfigProvider).value?.paperWidth ?? PaperWidth.mm58;
    final t = _template;

    return LargeTitlePage(
      title: 'Struk & Printer',
      backLabel: 'Pengaturan',
      onBack: () => context.go(AppRoutes.pengaturan),
      slivers: [
        SliverToBoxAdapter(
          child: t == null
              ? const SizedBox(height: 240, child: LoadingState())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final settings = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _templateSection(context, t),
                        const SizedBox(height: AppSpacing.xl),
                        PrinterSettingsSection(storeId: _storeId),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                    );
                    final preview = _previewPanel(context, paperWidth);
                    if (constraints.maxWidth >= 1100) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: settings),
                          const SizedBox(width: AppSpacing.xl),
                          SizedBox(width: 460, child: preview),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        preview,
                        const SizedBox(height: AppSpacing.xl),
                        settings,
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _previewPanel(BuildContext context, PaperWidth paperWidth) {
    final c = context.colors;
    final html = _previewHtml;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            'PRATINJAU · ${(_store?.name ?? '').toUpperCase()} · '
            '${paperWidth.label.toUpperCase()}',
            textAlign: TextAlign.center,
            style: AppTypography.footnote.copyWith(
              color: c.labelSecondary,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.xl,
            horizontal: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: c.fillSecondary,
            borderRadius: AppRadius.lgAll,
          ),
          child: Center(
            child: html == null
                ? const SizedBox(height: 200, child: LoadingState())
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF000000)
                                .withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ReceiptView(html: html, paperWidth: paperWidth),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Contoh data. Struk dicetak sebagai gambar hitam-putih selebar '
          '${paperWidth.dots} titik, persis seperti pratinjau ini. Lebar '
          'kertas mengikuti printer komputer ini.',
          textAlign: TextAlign.center,
          style: AppTypography.footnote.copyWith(color: c.labelTertiary),
        ),
      ],
    );
  }

  Widget _templateSection(BuildContext context, ReceiptTemplate t) {
    final c = context.colors;
    final multiStore = _stores.length > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsetGroupedSection(
          header: 'Bentuk Struk',
          footer: multiStore
              ? 'Setiap toko punya template dan logo sendiri. Struk faktur '
                    'mengikuti toko tempat transaksi.'
              : 'Logo dicetak hitam-putih; gambar besar otomatis diperkecil '
                    'ke lebar kertas.',
          dividerIndent: 58,
          children: [
            InsetGroupedTile(
              leading: TileIcon(
                icon: CupertinoIcons.building_2_fill,
                color: c.accent,
              ),
              title: 'Toko',
              value: _store?.name ?? '–',
              onPressed: multiStore ? _chooseStore : null,
            ),
            InsetGroupedTile(
              leading: TileIcon(
                icon: CupertinoIcons.photo,
                color: c.labelSecondary,
              ),
              title: 'Logo',
              subtitle: t.logo == null
                  ? 'Belum ada (PNG/JPG, maks. 5 MB)'
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (t.logo != null) ...[
                    ClipRRect(
                      borderRadius: AppRadius.smAll,
                      child: Container(
                        color: const Color(0xFFFFFFFF),
                        padding: const EdgeInsets.all(2),
                        child: Image(
                          image: ReceiptWidgetFactory.providerFor(t.logo!)!,
                          height: 32,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AppButton(
                      label: 'Hapus',
                      variant: AppButtonVariant.plain,
                      destructive: true,
                      size: AppButtonSize.small,
                      onPressed: () =>
                          _setTemplate(t.copyWith(logo: () => null)),
                    ),
                  ],
                  AppButton(
                    label: t.logo == null ? 'Pilih Logo…' : 'Ganti…',
                    variant: AppButtonVariant.tinted,
                    size: AppButtonSize.small,
                    onPressed: _pickLogo,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        InsetGroupedSection(
          header: 'Template HTML + CSS',
          footer:
              'Tulis HTML biasa; CSS boleh di <style> atau style="…". '
              'Variabel {{…}} diisi data faktur, klik daftar di atas untuk '
              'menyisipkan. Lebar halaman: 384 piksel (58 mm) atau 576 '
              '(80 mm). Gambar dari internet tidak dimuat; pakai Logo.',
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Variabel',
                    style: AppTypography.footnote.copyWith(
                      color: c.labelSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final (name, desc) in ReceiptVariables.all)
                        _VariableChip(
                          name: name,
                          description: desc,
                          onTap: () =>
                              _insertVariable(name.replaceAll('…', '')),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  CupertinoTextField(
                    key: const ValueKey('receipt-html-editor'),
                    controller: _editor,
                    focusNode: _editorFocus,
                    minLines: 16,
                    maxLines: 28,
                    keyboardType: TextInputType.multiline,
                    onChanged: _onEditorChanged,
                    style: _codeStyle.copyWith(color: c.label),
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: c.fill,
                      borderRadius: AppRadius.mdAll,
                    ),
                  ),
                  if (_templateError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ErrorBanner(message: _templateError!),
                  ],
                  if (ReceiptSections.missing(_editor.text) case final missing
                      when missing.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: c.warning.withValues(alpha: 0.12),
                        borderRadius: AppRadius.mdAll,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Template ini belum punya bagian '
                            '${missing.join(' dan ')}. Saat dicetak, bagian '
                            'itu ditambahkan otomatis (judul NOTA RETUR di '
                            'atas, rincian bayar terpisah di bawah).',
                            style: AppTypography.footnote.copyWith(
                              color: c.label,
                            ),
                          ),
                          AppButton(
                            label: 'Tambahkan ke Template',
                            icon: CupertinoIcons.plus_circle,
                            variant: AppButtonVariant.plain,
                            size: AppButtonSize.small,
                            onPressed: _addMissingSections,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      AppButton(
                        label: 'Kembalikan Template Bawaan',
                        icon: CupertinoIcons.arrow_counterclockwise,
                        variant: AppButtonVariant.plain,
                        onPressed: _resetTemplate,
                      ),
                      if (multiStore)
                        AppButton(
                          label: 'Terapkan Template ke Semua Toko',
                          icon: CupertinoIcons.square_on_square,
                          variant: AppButtonVariant.plain,
                          onPressed: _applyToAll,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static const _codeStyle = TextStyle(
    fontFamily: 'Menlo',
    fontFamilyFallback: ['Consolas', 'Courier New', 'monospace'],
    fontSize: 13,
    height: 1.45,
  );
}

class _VariableChip extends StatelessWidget {
  const _VariableChip({
    required this.name,
    required this.description,
    required this.onTap,
  });

  final String name;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: description,
      child: PressableScale(
        onPressed: onTap,
        pressedScale: 0.95,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: c.accentTint,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            name,
            style: _ReceiptSettingsPageState._codeStyle.copyWith(
              fontSize: 12,
              color: c.accent,
            ),
          ),
        ),
      ),
    );
  }
}
