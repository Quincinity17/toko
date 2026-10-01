import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/number_input.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/option_picker.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/product_repository.dart';
import '../domain/product.dart';
import 'product_providers.dart';

/// Form tambah (`existing == null`) atau ubah barang.
Future<void> showProductFormSheet(BuildContext context, {Product? existing}) {
  return AppDialogs.sheet<void>(
    context,
    title: existing == null ? 'Barang Baru' : 'Ubah Barang',
    maxWidth: 720,
    builder: (_) => _ProductForm(existing: existing),
  );
}

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({this.existing});

  final Product? existing;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  Product? get _p => widget.existing;

  late final _code = TextEditingController(text: _p?.code);
  late final _barcode = TextEditingController(text: _p?.barcode);
  late final _name = TextEditingController(text: _p?.name);
  late final _buy = TextEditingController(
    text: _p == null ? '' : Fmt.number(_p!.purchasePrice),
  );
  late final _sell = TextEditingController(
    text: _p == null ? '' : Fmt.number(_p!.sellingPrice),
  );
  late final _stock = TextEditingController(
    text: _p == null ? '' : Fmt.number(_p!.stock),
  );
  late final _minStock = TextEditingController(
    text: _p == null || _p!.minStock == 0 ? '' : Fmt.number(_p!.minStock),
  );

  late String? _category = _p?.categoryName;
  late String? _unit = _p?.unitName ?? 'PCS';
  late bool _active = _p?.isActive ?? true;

  final _errors = <String, String?>{};
  String? _error;
  bool _saving = false;

  List<TextEditingController> get _controllers => [
    _code,
    _barcode,
    _name,
    _buy,
    _sell,
    _stock,
    _minStock,
  ];

  @override
  void initState() {
    super.initState();
    // Margin dihitung ulang setiap harga berubah.
    _buy.addListener(_refresh);
    _sell.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  int? _money(TextEditingController c) =>
      c.text.trim().isEmpty ? null : parseIdNumber(c.text)?.round();

  double? _qty(TextEditingController c) =>
      c.text.trim().isEmpty ? null : parseIdNumber(c.text);

  bool _validate() {
    _errors
      ..clear()
      ..addAll({
        'code': ProductRules.code(_code.text),
        'barcode': ProductRules.barcode(_barcode.text),
        'name': ProductRules.name(_name.text),
        'sell': ProductRules.price(_money(_sell), label: 'Harga jual'),
        'buy': _buy.text.trim().isNotEmpty && _money(_buy) == null
            ? 'Format angka tidak valid.'
            : null,
        'stock': _stock.text.trim().isNotEmpty && _qty(_stock) == null
            ? 'Format angka tidak valid.'
            : null,
        'minStock': _minStock.text.trim().isNotEmpty && _qty(_minStock) == null
            ? 'Format angka tidak valid.'
            : ProductRules.minStock(_qty(_minStock)),
      });
    setState(() => _error = null);
    return _errors.values.every((e) => e == null);
  }

  Future<void> _save() async {
    if (!_validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(productRepositoryProvider)
          .save(
            actor: ref.read(authControllerProvider)!,
            id: _p?.id,
            draft: ProductDraft(
              code: _code.text,
              barcode: _barcode.text,
              name: _name.text,
              categoryName: _category,
              unitName: _unit,
              purchasePrice: _money(_buy) ?? 0,
              sellingPrice: _money(_sell)!,
              stock: _qty(_stock) ?? 0,
              minStock: _qty(_minStock) ?? 0,
              isActive: _active,
            ),
          );
      if (mounted) Navigator.pop(context);
    } on ProductFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'Hapus ${_p!.name}?',
      message:
          'Barang yang belum pernah terjual dihapus permanen. Barang yang '
          'sudah pernah terjual hanya dinonaktifkan agar faktur lama tetap utuh.',
      confirmLabel: 'Hapus',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final result = await ref
          .read(productRepositoryProvider)
          .remove(actor: ref.read(authControllerProvider)!, id: _p!.id);
      if (!mounted) return;
      Navigator.pop(context);
      if (result == ProductRemoval.deactivated) {
        await AppDialogs.alert(
          context,
          title: 'Barang dinonaktifkan',
          message:
              '${_p!.name} sudah pernah terjual, jadi tidak dihapus. Barang '
              'disembunyikan dari kasir dan bisa diaktifkan lagi lewat filter '
              '"Nonaktif".',
        );
      }
    } on ProductFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickCategory() async {
    final cats = ref.read(categoriesProvider).value ?? const [];
    final pick = await showOptionPicker(
      context,
      title: 'Kategori',
      options: [for (final (_, name) in cats) name],
      selected: _category,
      allowCreate: true,
      clearLabel: 'Tanpa kategori',
    );
    if (pick != null) setState(() => _category = pick.value);
  }

  Future<void> _pickUnit() async {
    final units = ref.read(unitNamesProvider).value ?? const [];
    final pick = await showOptionPicker(
      context,
      title: 'Satuan',
      options: units,
      selected: _unit,
      allowCreate: true,
      clearLabel: 'Tanpa satuan',
    );
    if (pick != null) setState(() => _unit = pick.value?.toUpperCase());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Muat daftar kategori & satuan lebih awal untuk picker.
    ref.watch(categoriesProvider);
    ref.watch(unitNamesProvider);

    final buy = _money(_buy) ?? 0;
    final sell = _money(_sell);
    final marginWarning = sell == null
        ? null
        : ProductRules.marginWarning(buy, sell);

    Widget pair(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: b),
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _name,
            label: 'Nama barang',
            placeholder: 'mis. Kecap Bango 220ml',
            autofocus: widget.existing == null,
            errorText: _errors['name'],
          ),
          const SizedBox(height: AppSpacing.md),
          pair(
            AppTextField(
              controller: _code,
              label: 'Kode',
              placeholder: 'mis. BRG021',
              errorText: _errors['code'],
            ),
            AppTextField(
              controller: _barcode,
              label: 'Barcode (opsional)',
              placeholder: 'Scan atau ketik',
              prefixIcon: CupertinoIcons.barcode,
              errorText: _errors['barcode'],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          InsetGroupedSection(
            children: [
              InsetGroupedTile(
                title: 'Kategori',
                value: _category ?? 'Tanpa kategori',
                onPressed: _pickCategory,
              ),
              InsetGroupedTile(
                title: 'Satuan',
                value: _unit ?? 'Tanpa satuan',
                onPressed: _pickUnit,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          pair(
            AppTextField(
              controller: _buy,
              label: 'Harga beli (Rp)',
              placeholder: '0',
              errorText: _errors['buy'],
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
            ),
            AppTextField(
              controller: _sell,
              label: 'Harga jual (Rp)',
              placeholder: '0',
              errorText: _errors['sell'],
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahInputFormatter()],
            ),
          ),
          if (sell != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              marginWarning ??
                  'Untung ${Fmt.rupiah(sell - buy)} per ${_unit ?? 'barang'}'
                      '${buy > 0 ? ' (${Fmt.number(((sell - buy) / buy * 100).round())}%)' : ''}',
              style: AppTypography.footnote.copyWith(
                color: marginWarning == null ? c.success : c.warning,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          pair(
            AppTextField(
              controller: _stock,
              label: 'Stok',
              placeholder: '0',
              errorText: _errors['stock'],
              helper: widget.existing == null
                  ? null
                  : 'Perubahan dicatat di riwayat stok.',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            AppTextField(
              controller: _minStock,
              label: 'Stok minimum (opsional)',
              placeholder: '0',
              errorText: _errors['minStock'],
              helper: 'Ditandai "stok menipis" jika stok ≤ angka ini.',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: AppSpacing.lg),
            InsetGroupedSection(
              children: [
                InsetGroupedTile(
                  title: 'Barang aktif',
                  subtitle: _active
                      ? 'Bisa dijual di kasir'
                      : 'Disembunyikan dari kasir',
                  trailing: CupertinoSwitch(
                    value: _active,
                    activeTrackColor: c.success,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _active = v),
                  ),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: widget.existing == null ? 'Simpan Barang' : 'Simpan',
            size: AppButtonSize.large,
            expand: true,
            loading: _saving,
            onPressed: _save,
          ),
          if (widget.existing != null) ...[
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: 'Hapus Barang',
              variant: AppButtonVariant.plain,
              destructive: true,
              expand: true,
              onPressed: _saving ? null : _remove,
            ),
          ],
        ],
      ),
    );
  }
}
