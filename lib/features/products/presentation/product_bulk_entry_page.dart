import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/number_input.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/option_picker.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../stores/data/store_repository.dart';
import '../../stores/domain/store.dart';
import '../../stores/presentation/store_scope.dart';
import '../data/product_import_service.dart';
import '../data/product_repository.dart';
import '../domain/bulk_entry.dart';
import '../domain/code_sequence.dart';
import '../domain/price_markup.dart';
import '../domain/product_import.dart';
import 'similar_names_dialog.dart';

/// Lebar kolom; `null` = mengisi sisa ruang (nama barang).
const _widths = <BulkColumn, double?>{
  BulkColumn.code: 150,
  BulkColumn.barcode: 150,
  BulkColumn.name: null,
  BulkColumn.category: 150,
  BulkColumn.unit: 80,
  BulkColumn.purchasePrice: 110,
  BulkColumn.markup: 84,
  BulkColumn.sellingPrice: 110,
  BulkColumn.stock: 80,
};
const _noWidth = 40.0, _deleteWidth = 40.0, _nameMinWidth = 220.0;
const _minTableWidth =
    _noWidth + _deleteWidth + _nameMinWidth + 150 * 3 + 80 * 2 + 110 * 2 + 84;
const _rowsPerBatch = 10;

/// Isian satu baris tabel.
class _Row {
  _Row() {
    for (final c in BulkColumn.values) {
      text[c] = TextEditingController();
      focus[c] = FocusNode();
    }
  }

  /// Baris berisi [values] (dari draf).
  factory _Row.from(BulkRowValues values) {
    final row = _Row();
    for (final MapEntry(:key, :value) in values.entries) {
      row.text[key]!.text = value;
    }
    return row;
  }

  final text = <BulkColumn, TextEditingController>{};
  final focus = <BulkColumn, FocusNode>{};

  /// Harga jual terakhir dihitung dari Untung % (ikut harga beli).
  bool markupDriven = false;
  List<String> errors = const [];

  /// Peringatan nama mirip (oranye); tidak menghalangi simpan.
  List<String> warnings = const [];

  /// Nama yang sudah diperingatkan lalu dipilih "Periksa Lagi"; Simpan
  /// berikutnya dengan nama sama tidak diperingatkan lagi.
  String? warnedName;

  BulkRowValues get values => {
    for (final c in BulkColumn.values) c: text[c]!.text,
  };

  bool get isBlank => BulkEntry.isBlank(values);

  void dispose() {
    for (final c in text.values) {
      c.dispose();
    }
    for (final f in focus.values) {
      f.dispose();
    }
  }
}

/// Produk › Input Tabel: mengetik banyak barang baru sekaligus seperti di
/// Excel (Tab = kolom berikutnya, Enter = baris berikutnya). Aturan dan
/// penyimpanan sama dengan import ([BulkEntry.validate]).
class ProductBulkEntryPage extends ConsumerStatefulWidget {
  const ProductBulkEntryPage({super.key});

  @override
  ConsumerState<ProductBulkEntryPage> createState() =>
      _ProductBulkEntryPageState();
}

class _ProductBulkEntryPageState extends ConsumerState<ProductBulkEntryPage> {
  final _rows = <_Row>[for (var i = 0; i < _rowsPerBatch; i++) _Row()];
  int? _stockStoreId;
  bool _saving = false;

  /// Disimpan di initState: `ref` tidak boleh dipakai di dispose.
  late final ProductRepository _repo;

  /// Jumlah baris draf yang dilanjutkan (untuk keterangan); 0 = tidak ada.
  int _restored = 0;

  /// Isian disimpan sebagai draf saat halaman ditutup (juga lewat sidebar),
  /// kecuali user memilih "Buang isian".
  bool _keepOnExit = true;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(productRepositoryProvider);
    _repo.loadBulkDraft().then((draft) {
      // Jangan menimpa bila user sudah mulai mengetik.
      if (!mounted || draft.isEmpty || _rows.any((r) => !r.isBlank)) return;
      setState(() {
        _replaceRows([for (final v in draft) _Row.from(v)]);
        _restored = draft.length;
      });
    });
  }

  @override
  void dispose() {
    if (_keepOnExit) _repo.saveBulkDraft([for (final r in _rows) r.values]);
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  /// Mengganti semua baris (minimal [_rowsPerBatch], sisanya kosong).
  void _replaceRows(List<_Row> rows) {
    final old = [..._rows];
    _rows
      ..clear()
      ..addAll(rows)
      ..addAll([for (var i = rows.length; i < _rowsPerBatch; i++) _Row()]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final r in old) {
        r.dispose();
      }
    });
  }

  Future<void> _discardDraft() async {
    final ok = await AppDialogs.confirm(
      context,
      title: 'Buang draf?',
      message: 'Semua isian tabel dihapus.',
      confirmLabel: 'Buang',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() {
      _replaceRows(const []);
      _restored = 0;
    });
    await _repo.clearBulkDraft();
  }

  List<Store> get _activeStores =>
      (ref.read(storesProvider).value ?? const <Store>[])
          .where((s) => s.isActive)
          .toList();

  /// Toko tujuan stok: pilihan user, toko yang sedang dipakai, atau
  /// satu-satunya toko aktif.
  int? get _stockStore {
    if (_stockStoreId != null) return _stockStoreId;
    final scope = ref.read(storeScopeProvider);
    if (scope != null) return scope;
    final stores = _activeStores;
    return stores.length == 1 ? stores.first.id : null;
  }

  Future<int?> _pickStockStore() async {
    final stores = _activeStores;
    final current = stores.where((s) => s.id == _stockStore).firstOrNull;
    final pick = await showOptionPicker(
      context,
      title: 'Stok masuk ke toko',
      options: [for (final s in stores) s.name],
      selected: current?.name,
    );
    final name = pick?.value;
    if (name == null) return null;
    final id = stores.firstWhere((s) => s.name == name).id;
    setState(() => _stockStoreId = id);
    return id;
  }

  void _addRows([int count = _rowsPerBatch]) =>
      setState(() => _rows.addAll([for (var i = 0; i < count; i++) _Row()]));

  void _removeRow(_Row row) {
    setState(() => _rows.remove(row));
    row.dispose();
    if (_rows.isEmpty) _addRows();
  }

  /// Enter: kolom yang sama di baris berikutnya (baris baru bila perlu).
  void _moveDown(_Row row, BulkColumn column) {
    var i = _rows.indexOf(row) + 1;
    if (i >= _rows.length) _addRows();
    _rows[i].focus[column]!.requestFocus();
  }

  static String _percentText(int buy, int sell) =>
      switch (PriceMarkup.percent(buy, sell)) {
        final p? => Fmt.number(p),
        null => '',
      };

  int? _money(_Row row, BulkColumn c) =>
      parseIdNumber(row.text[c]!.text)?.round();

  void _onChanged(_Row row, BulkColumn column) {
    final sell = row.text[BulkColumn.sellingPrice]!;
    final markup = row.text[BulkColumn.markup]!;
    switch (column) {
      case BulkColumn.markup:
        row.markupDriven = true;
        if (BulkEntry.sellingFromMarkup(row.values) case final v?) {
          sell.text = Fmt.number(v);
        }
      case BulkColumn.purchasePrice:
        if (row.markupDriven) {
          if (BulkEntry.sellingFromMarkup(row.values) case final v?) {
            sell.text = Fmt.number(v);
          }
        } else if (_money(row, BulkColumn.sellingPrice) case final s?) {
          markup.text = _percentText(
            _money(row, BulkColumn.purchasePrice) ?? 0,
            s,
          );
        }
      case BulkColumn.sellingPrice:
        row.markupDriven = false;
        markup.text = _percentText(
          _money(row, BulkColumn.purchasePrice) ?? 0,
          _money(row, BulkColumn.sellingPrice) ?? 0,
        );
      default:
        break;
    }
    if (row.errors.isNotEmpty || row.warnings.isNotEmpty) {
      setState(() {
        row.errors = const [];
        row.warnings = const [];
      });
    }
  }

  /// Mengisi barcode kosong pada baris yang sudah terisi, melanjutkan
  /// barcode terakhir (+1), lihat [CodeSequence].
  Future<void> _autoCodes() async {
    final targets = [
      for (final r in _rows)
        if (!r.isBlank && r.text[BulkColumn.code]!.text.trim().isEmpty) r,
    ];
    if (targets.isEmpty) {
      await AppDialogs.alert(
        context,
        title: 'Tidak ada yang diisi',
        message:
            'Barcode otomatis mengisi baris yang sudah ada nama barangnya '
            'tetapi barcodenya masih kosong.',
      );
      return;
    }
    final taken = [
      for (final r in _rows.reversed)
        if (r.text[BulkColumn.code]!.text.trim() case final c when c.isNotEmpty)
          c,
      ...await ref.read(productRepositoryProvider).codesNewestFirst(),
    ];
    if (!mounted) return;
    for (final row in targets) {
      final next = CodeSequence.next(taken);
      if (next == null) {
        await AppDialogs.alert(
          context,
          title: 'Belum ada barcode bernomor',
          message:
              'Ketik barcode baris pertama secara manual (mis. BMM0000001), '
              'lalu tekan Barcode Otomatis lagi.',
        );
        return;
      }
      row.text[BulkColumn.code]!.text = next.next;
      taken.insert(0, next.next);
    }
    setState(() {
      for (final r in targets) {
        r.errors = const [];
      }
    });
  }

  Future<void> _save() async {
    final actor = ref.read(authControllerProvider)!;
    final service = ref.read(productImportServiceProvider);
    final checked = BulkEntry.validate([
      for (final r in _rows) r.values,
    ], await service.existingIndex());
    if (!mounted) return;
    setState(() {
      for (final r in _rows) {
        r.errors = const [];
      }
      for (final c in checked.where((c) => !c.isValid)) {
        _rows[c.rowNumber - 1].errors = c.errors;
      }
    });
    if (checked.isEmpty) {
      await AppDialogs.alert(
        context,
        title: 'Tabel masih kosong',
        message: 'Ketik minimal satu barang: barcode, nama, dan harga jual.',
      );
      return;
    }
    final valid = checked.where((c) => c.isValid).toList();
    if (valid.isEmpty) {
      await AppDialogs.alert(
        context,
        title: 'Belum ada yang bisa disimpan',
        message: 'Perbaiki baris yang ditandai merah.',
      );
      return;
    }

    // Nama sama / mirip barang lain: peringatan sekali, saat menyimpan.
    final similar =
        (await ref.read(productRepositoryProvider).similarNames([
          for (final v in valid) (v.rowNumber, v.draft!.name.trim()),
        ])).where((f) {
          final row = _rows[f.key - 1];
          return row.warnedName != f.name;
        }).toList();
    if (!mounted) return;
    if (similar.isNotEmpty) {
      final ok = await showSimilarNamesConfirm(context, similar, showRow: true);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          for (final f in similar) {
            final row = _rows[f.key - 1];
            row.warnedName = f.name;
            row.warnings = [
              ...row.warnings,
              '${f.exact ? 'Sama dengan' : 'Mirip dengan'} ${f.matchLabel}',
            ];
          }
        });
        return;
      }
    }

    var store = _stockStore;
    if (store == null && valid.any((r) => r.stock != 0)) {
      store = await _pickStockStore();
      if (store == null || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      final result = await service.run(
        actor: actor,
        rows: valid,
        existingAction: ExistingProductAction.skip,
        stockStoreId: store,
      );
      if (!mounted) return;
      final saved = {for (final v in valid) _rows[v.rowNumber - 1]};
      setState(() {
        _rows.removeWhere(saved.contains);
        // Baris kosong di antara baris error juga dibersihkan.
        _rows.removeWhere((r) => r.isBlank && r.errors.isEmpty);
        final pad = math.max(0, _rowsPerBatch - _rows.length);
        _rows.addAll([for (var i = 0; i < pad; i++) _Row()]);
      });
      // Controller baris tersimpan dibuang setelah frame ini.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final r in saved) {
          r.dispose();
        }
      });
      final failed = checked.length - valid.length;
      await AppDialogs.alert(
        context,
        title: '${Fmt.number(result.inserted)} barang tersimpan',
        message: [
          if (result.newCategories > 0)
            '${result.newCategories} kategori baru dibuat.',
          if (result.newUnits > 0) '${result.newUnits} satuan baru dibuat.',
          if (failed > 0)
            '$failed baris belum tersimpan karena ada kesalahan '
                '(ditandai merah).',
        ].join('\n'),
      );
    } on ProductFailure catch (e) {
      if (mounted) {
        await AppDialogs.alert(context, title: 'Gagal', message: e.message);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Keluar dengan isian belum disimpan: simpan sebagai draf (dilanjutkan
  /// saat halaman dibuka lagi) atau buang.
  Future<void> _back() async {
    final filled = _rows.where((r) => !r.isBlank).length;
    if (filled > 0) {
      final keep = await AppDialogs.actionSheet<bool>(
        context,
        title: 'Isian belum disimpan',
        message:
            '$filled baris belum disimpan ke daftar barang. Simpan sebagai '
            'draf untuk dilanjutkan nanti?',
        options: const [
          ActionSheetOption(label: 'Simpan sebagai Draf', value: true),
          ActionSheetOption(
            label: 'Buang Isian',
            value: false,
            destructive: true,
          ),
        ],
      );
      if (keep == null || !mounted) return;
      _keepOnExit = keep;
      if (!keep) await _repo.clearBulkDraft();
      if (!mounted) return;
    }
    context.go(AppRoutes.produk);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final stores = (ref.watch(storesProvider).value ?? const <Store>[])
        .where((s) => s.isActive)
        .toList();
    final storeName = stores
        .where((s) => s.id == _stockStore)
        .firstOrNull
        ?.name;

    return LargeTitlePage(
      title: 'Input Tabel',
      backLabel: 'Produk',
      onBack: _saving ? null : _back,
      actions: [
        AppButton(
          label: 'Barcode Otomatis',
          icon: CupertinoIcons.wand_stars,
          variant: AppButtonVariant.gray,
          onPressed: _saving ? null : _autoCodes,
        ),
        AppButton(
          label: 'Simpan',
          icon: CupertinoIcons.checkmark_alt,
          loading: _saving,
          onPressed: _save,
        ),
      ],
      bottom: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_restored > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.doc_on_clipboard_fill,
                  size: 16,
                  color: c.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  'Melanjutkan draf ($_restored baris)',
                  style: AppTypography.footnote.copyWith(
                    color: c.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                AppButton(
                  label: 'Buang Draf',
                  variant: AppButtonVariant.plain,
                  size: AppButtonSize.small,
                  destructive: true,
                  onPressed: _discardDraft,
                ),
              ],
            ),
          Text(
            'Tab pindah kolom, Enter pindah baris. Baris kosong diabaikan. '
            'Isi Untung % untuk menghitung harga jual. Isian otomatis '
            'disimpan sebagai draf saat keluar.',
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
          if (stores.length > 1)
            AppButton(
              label: 'Stok masuk ke: ${storeName ?? 'pilih toko'}',
              icon: CupertinoIcons.building_2_fill,
              variant: AppButtonVariant.gray,
              size: AppButtonSize.small,
              onPressed: _pickStockStore,
            ),
        ],
      ),
      slivers: [
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = math.max(constraints.maxWidth, _minTableWidth);
              final table = SizedBox(width: width, child: _table(c));
              return width > constraints.maxWidth
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: table,
                    )
                  : table;
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Tambah $_rowsPerBatch Baris',
                icon: CupertinoIcons.add,
                variant: AppButtonVariant.plain,
                onPressed: () => _addRows(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Sel dengan garis pemisah kolom di kiri.
  Widget _cell(AppColors c, BulkColumn column, Widget child) {
    final cell = _divider(c, child);
    return switch (_widths[column]) {
      final w? => SizedBox(width: w, child: cell),
      null => Expanded(child: cell),
    };
  }

  Widget _table(AppColors c) {
    final header = AppTypography.footnote.copyWith(
      color: c.labelSecondary,
      fontWeight: FontWeight.w600,
    );
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _noWidth,
                  child: Center(
                    child: Text(
                      'No',
                      style: header,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                for (final col in BulkColumn.values)
                  _cell(
                    c,
                    col,
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        col.label,
                        style: header,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: col.isNumber
                            ? TextAlign.right
                            : TextAlign.left,
                      ),
                    ),
                  ),
                _divider(c, const SizedBox(width: _deleteWidth)),
              ],
            ),
          ),
          for (final (i, row) in _rows.indexed) ...[
            Container(height: 0.5, color: c.separator),
            _rowView(c, i, row),
          ],
        ],
      ),
    );
  }

  /// Garis pemisah kolom di kiri [child]. Baris memakai IntrinsicHeight +
  /// stretch supaya garis setinggi baris.
  Widget _divider(AppColors c, Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: c.separator, width: 0.5)),
    ),
    child: child,
  );

  Widget _rowView(AppColors c, int index, _Row row) {
    final hasError = row.errors.isNotEmpty;
    return Container(
      key: ObjectKey(row),
      color: hasError ? c.danger.withValues(alpha: 0.08) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _noWidth,
                  child: Center(
                    child: Text(
                      '${index + 1}',
                      style: AppTypography.footnote.copyWith(
                        color: hasError ? c.danger : c.labelTertiary,
                      ),
                    ),
                  ),
                ),
                for (final col in BulkColumn.values)
                  _cell(c, col, _input(c, row, col)),
                _divider(
                  c,
                  SizedBox(
                    width: _deleteWidth,
                    child: row.isBlank
                        ? null
                        : PressableScale(
                            onPressed: () => _removeRow(row),
                            child: Center(
                              child: Icon(
                                CupertinoIcons.xmark_circle_fill,
                                size: 18,
                                color: c.labelTertiary,
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (row.warnings.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                _noWidth + 8,
                0,
                AppSpacing.md,
                hasError ? 2 : AppSpacing.sm,
              ),
              child: Text(
                row.warnings.join(' · '),
                style: AppTypography.caption.copyWith(color: c.warning),
              ),
            ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _noWidth + 8,
                0,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Text(
                row.errors.join(' · '),
                style: AppTypography.caption.copyWith(color: c.danger),
              ),
            ),
        ],
      ),
    );
  }

  Widget _input(AppColors c, _Row row, BulkColumn col) {
    return CupertinoTextField(
      controller: row.text[col],
      focusNode: row.focus[col],
      placeholder: switch (col) {
        BulkColumn.unit => BulkEntry.defaultUnit,
        BulkColumn.category => 'A, B',
        _ => null,
      },
      placeholderStyle: AppTypography.subheadline.copyWith(
        color: c.labelTertiary,
      ),
      style: AppTypography.subheadline.copyWith(color: c.label),
      textAlign: col.isNumber ? TextAlign.right : TextAlign.left,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: const BoxDecoration(),
      keyboardType: col.isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      inputFormatters: col.isMoney ? [RupiahInputFormatter()] : null,
      textInputAction: TextInputAction.next,
      onChanged: (_) {
        _onChanged(row, col);
        // Tombol hapus baris muncul/hilang mengikuti isi.
        setState(() {});
      },
      // Enter turun ke baris berikutnya (bukan pindah kolom bawaan).
      onEditingComplete: () {},
      onSubmitted: (_) => _moveDown(row, col),
    );
  }
}
