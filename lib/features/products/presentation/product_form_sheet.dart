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
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../stores/data/store_repository.dart';
import '../../stores/domain/store.dart';
import '../data/product_repository.dart';
import '../data/tag_repository.dart';
import '../domain/product.dart';
import '../domain/price_markup.dart';
import '../domain/product_changes.dart';
import '../domain/tag.dart';
import 'tag_chip.dart';
import 'tag_picker.dart';
import 'product_providers.dart';
import 'similar_names_dialog.dart';

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
  // Harga beli opsional: 0 = belum diketahui, ditampilkan kosong.
  late final _buy = TextEditingController(
    text: _p == null || _p!.purchasePrice == 0
        ? ''
        : Fmt.number(_p!.purchasePrice),
  );
  late final _sell = TextEditingController(
    text: _p == null ? '' : Fmt.number(_p!.defaultSellingPrice),
  );

  /// Persen untung terhadap harga beli; mengisi harga jual otomatis.
  late final _markup = TextEditingController(
    text: switch (_p) {
      final p? => _percentText(p.purchasePrice, p.defaultSellingPrice),
      null => '',
    },
  );

  /// Harga jual terakhir dihitung dari persen (bukan diketik), jadi ikut
  /// berubah saat harga beli diubah.
  bool _markupDriven = false;

  /// Isian per toko (stok, harga khusus), dibuat saat toko pertama tampil.
  final _storeStock = <int, TextEditingController>{};
  final _storePrice = <int, TextEditingController>{};

  /// Nilai tersimpan per toko; `null` selama dimuat (barang lama).
  Map<int, ({double stock, int? price})>? _saved;
  late final _minStock = TextEditingController(
    text: _p == null || _p!.minStock == 0 ? '' : Fmt.number(_p!.minStock),
  );

  late List<String> _tags = [for (final t in _p?.tags ?? const <Tag>[]) t.name];
  late String? _unit = _p?.unitName ?? 'PCS';
  late bool _active = _p?.isActive ?? true;

  /// Barcode diisi otomatis (+1 dari barcode terakhir); hanya barang baru.
  bool _autoCode = false;

  /// Barcode yang menjadi dasar nomor otomatis, untuk keterangan.
  String? _autoBasis;

  /// Nama yang sudah diperingatkan mirip lalu dipilih "Periksa Lagi";
  /// Simpan berikutnya dengan nama yang sama tidak diperingatkan lagi.
  String? _warnedName;

  final _errors = <String, String?>{};
  String? _error;
  bool _saving = false;

  List<TextEditingController> get _controllers => [
    _code,
    _barcode,
    _name,
    _buy,
    _sell,
    _minStock,
    _markup,
    ..._storeStock.values,
    ..._storePrice.values,
  ];

  @override
  void initState() {
    super.initState();
    // Margin dihitung ulang setiap harga berubah.
    _buy.addListener(_refresh);
    _sell.addListener(_refresh);
    if (_p == null) {
      _saved = const {};
      ref.read(productRepositoryProvider).autoCodeEnabled().then((on) {
        if (on && mounted) _setAutoCode(true, remember: false);
      });
    } else {
      ref.read(productRepositoryProvider).storeValues(_p!.id).then((v) {
        if (!mounted) return;
        setState(() => _saved = v);
        for (final MapEntry(key: id, value: c) in _storeStock.entries) {
          c.text = Fmt.number(v[id]?.stock ?? 0);
        }
        for (final MapEntry(key: id, value: c) in _storePrice.entries) {
          final price = v[id]?.price;
          c.text = price == null ? '' : Fmt.number(price);
        }
      });
    }
  }

  /// Membuat isian untuk toko [s] (sekali), terisi nilai tersimpan.
  void _ensureStoreFields(Store s) {
    final saved = _saved?[s.id];
    _storeStock.putIfAbsent(
      s.id,
      () => TextEditingController(
        text: _p == null || _saved == null ? '' : Fmt.number(saved?.stock ?? 0),
      ),
    );
    _storePrice.putIfAbsent(
      s.id,
      () => TextEditingController(
        text: saved?.price == null ? '' : Fmt.number(saved!.price!),
      ),
    );
  }

  void _refresh() => setState(() {});

  static String _percentText(int buy, int sell) =>
      switch (PriceMarkup.percent(buy, sell)) {
        final p? => Fmt.number(p),
        null => '',
      };

  void _sellFromMarkup() {
    final pct = parseIdNumber(_markup.text);
    final sell = pct == null
        ? null
        : PriceMarkup.sellingPrice(_money(_buy) ?? 0, pct.toDouble());
    if (sell != null) _sell.text = Fmt.number(sell);
  }

  void _onBuyChanged(String _) {
    if (_markupDriven) {
      _sellFromMarkup();
    } else if (_money(_sell) case final sell?) {
      _markup.text = _percentText(_money(_buy) ?? 0, sell);
    }
  }

  void _onMarkupChanged(String _) {
    _markupDriven = true;
    _sellFromMarkup();
  }

  void _onSellChanged(String _) {
    _markupDriven = false;
    _markup.text = _percentText(_money(_buy) ?? 0, _money(_sell) ?? 0);
  }

  Future<void> _setAutoCode(bool on, {bool remember = true}) async {
    final repo = ref.read(productRepositoryProvider);
    if (remember) await repo.setAutoCode(on);
    if (!on) {
      if (mounted) setState(() => _autoCode = false);
      return;
    }
    await _fillAutoCode();
  }

  /// Mengisi barcode berikutnya; dipanggil lagi saat menyimpan supaya tetap
  /// terbaru.
  Future<void> _fillAutoCode() async {
    final next = await ref.read(productRepositoryProvider).nextCode();
    if (!mounted) return;
    setState(() {
      _autoCode = next != null;
      _autoBasis = next?.basedOn;
      if (next != null) {
        _code.text = next.next;
        _errors['code'] = null;
      } else {
        _errors['code'] =
            'Belum ada barcode berakhiran angka. Isi satu barang dulu, '
            'mis. BMM0000001.';
      }
    });
  }

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
        for (final MapEntry(key: id, value: c) in _storeStock.entries)
          'stock$id': c.text.trim().isNotEmpty && _qty(c) == null
              ? 'Format angka tidak valid.'
              : null,
        for (final MapEntry(key: id, value: c) in _storePrice.entries)
          'price$id': c.text.trim().isNotEmpty && _money(c) == null
              ? 'Format angka tidak valid.'
              : null,
        'minStock': _minStock.text.trim().isNotEmpty && _qty(_minStock) == null
            ? 'Format angka tidak valid.'
            : ProductRules.minStock(_qty(_minStock)),
      });
    setState(() => _error = null);
    return _errors.values.every((e) => e == null);
  }

  ProductDraft get _draft => ProductDraft(
    code: _code.text,
    barcode: _barcode.text,
    name: _name.text,
    unitName: _unit,
    purchasePrice: _money(_buy) ?? 0,
    sellingPrice: _money(_sell)!,
    minStock: _qty(_minStock) ?? 0,
    isActive: _active,
    tagNames: _tags,
  );

  List<StoreProductValues> get _storeValues => [
    for (final id in _storeStock.keys)
      StoreProductValues(
        storeId: id,
        stock: _qty(_storeStock[id]!) ?? 0,
        price: _money(_storePrice[id]!),
      ),
  ];

  Future<void> _save() async {
    if (_p == null && _autoCode) await _fillAutoCode();
    if (!mounted || _saved == null || !_validate()) return;
    final draft = _draft;
    final stores = _storeValues;

    // Ubah barang: tampilkan apa saja yang berubah dan minta konfirmasi.
    if (_p != null) {
      final changes = productChanges(
        before: _p!,
        beforeStores: _saved!,
        after: draft,
        afterStores: stores,
        storeNames: {
          for (final s in ref.read(storesProvider).value ?? const <Store>[])
            s.id: s.name,
        },
      );
      if (changes.isEmpty) {
        Navigator.pop(context);
        return;
      }
      final ok = await showChangesConfirm(context, _p!.name, changes);
      if (!ok || !mounted) return;
    }

    // Barang baru: peringatan nama sama / mirip (sekali, saat menyimpan).
    final name = draft.name.trim();
    if (_p == null && name != _warnedName) {
      final found = await ref.read(productRepositoryProvider).similarNames([
        (0, name),
      ]);
      if (!mounted) return;
      if (found.isNotEmpty) {
        final ok = await showSimilarNamesConfirm(context, found);
        if (!mounted) return;
        if (!ok) {
          _warnedName = name;
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(productRepositoryProvider)
          .save(
            actor: ref.read(authControllerProvider)!,
            id: _p?.id,
            draft: draft,
            stores: stores,
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

  Future<void> _pickTags() async {
    final picked = await showTagPicker(context, selected: _tags);
    if (picked != null) setState(() => _tags = picked);
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

  /// Baris Kategori: chip kategori terpilih (bisa dilepas) + ketuk untuk
  /// memilih (boleh lebih dari satu).
  Widget _tagTile() {
    final colors = {
      for (final t in ref.watch(tagsProvider).value ?? const <Tag>[])
        t.name.toLowerCase(): t.color,
    };
    return InsetGroupedTile(
      title: 'Kategori',
      value: _tags.isEmpty ? 'Tanpa kategori' : null,
      onPressed: _pickTags,
      showChevron: true,
      below: _tags.isEmpty
          ? null
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final name in _tags)
                  TagChip(
                    name: name,
                    color: colors[name.toLowerCase()] ?? TagColor.blue,
                    onRemove: () => setState(
                      () => _tags = [
                        for (final t in _tags)
                          if (t != name) t,
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Muat daftar kategori & satuan lebih awal untuk picker.
    ref.watch(tagsProvider);
    ref.watch(unitNamesProvider);
    final stores = (ref.watch(storesProvider).value ?? const <Store>[])
        .where((s) => s.isActive)
        .toList();
    stores.forEach(_ensureStoreFields);

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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: _code,
                  label: 'Barcode',
                  placeholder: 'mis. BMM0000001',
                  prefixIcon: CupertinoIcons.barcode,
                  enabled: !_autoCode,
                  helper: _autoCode && _autoBasis != null
                      ? 'Lanjutan dari $_autoBasis'
                      : null,
                  errorText: _errors['code'],
                ),
                if (_p == null)
                  _AutoCodeToggle(value: _autoCode, onChanged: _setAutoCode),
              ],
            ),
            AppTextField(
              controller: _barcode,
              label: 'Barcode bawaan (opsional)',
              placeholder: 'Barcode pabrik di kemasan',
              prefixIcon: CupertinoIcons.barcode_viewfinder,
              errorText: _errors['barcode'],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          InsetGroupedSection(
            children: [
              InsetGroupedTile(
                title: 'Satuan',
                value: _unit ?? 'Tanpa satuan',
                onPressed: _pickUnit,
              ),
              _tagTile(),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: AppTextField(
                  controller: _buy,
                  label: 'Harga beli (opsional)',
                  placeholder: 'Boleh dikosongkan',
                  errorText: _errors['buy'],
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  onChanged: _onBuyChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: AppTextField(
                  controller: _markup,
                  label: 'Untung (%)',
                  placeholder: buy > 0 ? 'mis. 25' : 'Isi harga beli',
                  enabled: buy > 0,
                  helper: buy > 0 ? 'Harga jual dihitung otomatis.' : null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: _onMarkupChanged,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 3,
                child: AppTextField(
                  controller: _sell,
                  label: 'Harga jual (Rp)',
                  placeholder: '0',
                  helper: 'Harga default semua toko.',
                  errorText: _errors['sell'],
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                  onChanged: _onSellChanged,
                ),
              ),
            ],
          ),
          if (sell != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              buy == 0
                  ? 'Harga beli belum diisi: untung belum bisa dihitung. '
                        'Bisa dilengkapi nanti.'
                  : marginWarning ??
                        'Untung ${Fmt.rupiah(sell - buy)} per '
                            '${_unit ?? 'barang'} '
                            '(${Fmt.number(((sell - buy) / buy * 100).round())}%)',
              style: AppTypography.footnote.copyWith(
                color: buy == 0
                    ? c.labelSecondary
                    : marginWarning == null
                    ? c.success
                    : c.warning,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          pair(
            AppTextField(
              controller: _minStock,
              label: 'Stok minimum (opsional)',
              placeholder: '0',
              errorText: _errors['minStock'],
              helper: 'Ditandai "stok menipis" jika stok toko ≤ angka ini.',
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'STOK & HARGA PER TOKO',
            style: AppTypography.footnote.copyWith(
              color: c.labelSecondary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (_saved == null)
            const SizedBox(height: 64, child: LoadingState())
          else
            for (final store in stores) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: c.fillSecondary,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      store.name,
                      style: AppTypography.headline.copyWith(color: c.label),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    pair(
                      AppTextField(
                        controller: _storeStock[store.id],
                        label: 'Stok',
                        placeholder: '0',
                        errorText: _errors['stock${store.id}'],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      AppTextField(
                        controller: _storePrice[store.id],
                        label: 'Harga khusus toko (Rp)',
                        placeholder: sell == null
                            ? 'Sama dengan default'
                            : Fmt.number(sell),
                        errorText: _errors['price${store.id}'],
                        keyboardType: TextInputType.number,
                        inputFormatters: [RupiahInputFormatter()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
          Text(
            widget.existing == null
                ? 'Harga khusus kosong = memakai harga default.'
                : 'Harga khusus kosong = memakai harga default. Perubahan '
                      'stok dicatat di riwayat stok.',
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
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

/// Popup konfirmasi perubahan barang: daftar isian lama → baru.
Future<bool> showChangesConfirm(
  BuildContext context,
  String productName,
  List<FieldChange> changes,
) async {
  final ok = await AppDialogs.popup<bool>(
    context,
    title: 'Simpan perubahan?',
    maxWidth: 520,
    builder: (ctx) => _ChangesView(name: productName, changes: changes),
  );
  return ok ?? false;
}

class _ChangesView extends StatelessWidget {
  const _ChangesView({required this.name, required this.changes});

  final String name;
  final List<FieldChange> changes;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final muted = AppTypography.subheadline.copyWith(color: c.labelSecondary);
    final value = AppTypography.subheadline.copyWith(
      color: c.label,
      fontFeatures: const [FontFeature.tabularFigures()],
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
          Text('${changes.length} perubahan pada $name:', style: muted),
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
              itemCount: changes.length,
              separatorBuilder: (_, _) =>
                  Container(height: 0.5, color: c.separator),
              itemBuilder: (_, i) {
                final ch = changes[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 130, child: Text(ch.label, style: muted)),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: ch.from,
                                style: value.copyWith(
                                  color: c.labelSecondary,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                              const TextSpan(text: '  →  '),
                              TextSpan(
                                text: ch.to,
                                style: value.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          style: value,
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
                  label: 'Simpan',
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

/// Centang "Otomatis": barcode = barcode terakhir + 1.
class _AutoCodeToggle extends StatelessWidget {
  const _AutoCodeToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressableScale(
      onPressed: () => onChanged(!value),
      pressedScale: 0.98,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoCheckbox(
              value: value,
              activeColor: c.accent,
              onChanged: (v) => onChanged(v ?? false),
            ),
            Flexible(
              child: Text(
                'Otomatis (+1 dari barcode terakhir)',
                style: AppTypography.footnote.copyWith(color: c.label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
