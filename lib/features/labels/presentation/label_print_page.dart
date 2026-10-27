import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/database/app_database.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/device.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/number_input.dart';
import '../../../core/utils/save_file.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/barcode_scanner.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../products/data/product_repository.dart';
import '../../products/domain/product.dart';
import '../../products/domain/product_pricing.dart';
import '../../sales/presentation/widgets/product_search_sheet.dart';
import '../../stores/presentation/store_scope.dart';
import '../../receipt/data/receipt_settings_repository.dart';
import '../data/label_pdf.dart';
import '../data/label_printer.dart';
import '../domain/label_layout.dart';
import 'label_queue.dart';
import 'label_view.dart';

const _kLayoutSetting = 'labels.layout';

/// Cetak label barcode & harga (Produk › Cetak Label). Hasilnya PDF: dicetak
/// lewat printer biasa (kertas stiker A4) atau printer label (rol).
class LabelPrintPage extends ConsumerStatefulWidget {
  const LabelPrintPage({super.key});

  @override
  ConsumerState<LabelPrintPage> createState() => _LabelPrintPageState();
}

class _LabelPrintPageState extends ConsumerState<LabelPrintPage> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  final _start = TextEditingController(text: '1');

  LabelLayout _layout = LabelLayout.presets.first;
  bool _showName = true;
  bool _showPrice = true;
  bool _showStore = false;

  /// Cetak barcode pabrik (EAN) bila barang punya.
  bool _factory = false;

  /// Daftar label (bisa diisi dari halaman Produk / Barang Masuk).
  List<LabelItem> get _items => ref.read(labelQueueProvider);
  LabelQueue get _queue => ref.read(labelQueueProvider.notifier);
  bool _busy = false;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    ref.read(appDatabaseProvider).settingsDao.get(_kLayoutSetting).then((id) {
      if (mounted && id != null) {
        setState(() => _layout = LabelLayout.byId(id));
      }
    });
  }

  @override
  void dispose() {
    _code.dispose();
    _codeFocus.dispose();
    _start.dispose();
    super.dispose();
  }

  int get _startAt => _layout.isRoll
      ? 1
      : (parseIdNumber(_start.text)?.round() ?? 1).clamp(1, _layout.perPage);

  int get _labelCount => _items.fold(0, (s, i) => s + i.copies);

  LabelOptions get _options => LabelOptions(
    showName: _showName,
    showPrice: _showPrice,
    storeName: _showStore ? ref.read(activeStoreProvider)?.name : null,
    startAt: _startAt,
    useFactoryBarcode: _factory,
  );

  void _add(Product product, {ProductUnit? unit}) {
    // Label kemasan memakai barcode & harga kemasannya.
    _queue.addProduct(product, unit: unit);
    setState(() {
      _codeError = null;
      _code.clear();
    });
  }

  Future<void> _submitCode([String? scanned]) async {
    final text = (scanned ?? _code.text).trim();
    if (text.isEmpty) return;
    final match = await ref
        .read(productRepositoryProvider)
        .scan(text, storeId: ref.read(storeScopeProvider));
    if (!mounted) return;
    if (match != null) {
      _add(match.product, unit: match.unit);
      if (!Device.isTouch) _codeFocus.requestFocus();
      return;
    }
    await _search(initial: text);
  }

  Future<void> _search({String initial = ''}) async {
    final picked = await showProductSearchSheet(context, initialQuery: initial);
    if (!mounted) return;
    if (picked == null) {
      if (initial.isNotEmpty) {
        setState(() => _codeError = 'Barang "$initial" tidak ditemukan.');
      }
      return;
    }
    // Barang dengan kemasan berbarcode: pilih label satuan mana.
    final packs = picked.units.where((u) => u.barcode != null).toList();
    if (packs.isEmpty) return _add(picked);
    final unitId = await AppDialogs.actionSheet<int>(
      context,
      title: 'Label ${picked.name}',
      options: [
        ActionSheetOption(
          label: '${picked.unitName ?? 'PCS'} · ${picked.code}',
          value: 0,
        ),
        for (final u in packs)
          ActionSheetOption(label: '${u.name} · ${u.barcode}', value: u.id!),
      ],
    );
    if (unitId == null || !mounted) return;
    _add(picked, unit: picked.unitById(unitId));
  }

  Future<void> _pickLayout() async {
    final id = await AppDialogs.actionSheet<String>(
      context,
      title: 'Ukuran label',
      options: [
        for (final l in LabelLayout.presets)
          ActionSheetOption(
            label: '${l.name}${l.id == _layout.id ? '  ✓' : ''}',
            value: l.id,
          ),
      ],
    );
    if (id == null || !mounted) return;
    setState(() => _layout = LabelLayout.byId(id));
    await ref.read(appDatabaseProvider).settingsDao.set(_kLayoutSetting, id);
  }

  Future<void> _editCopies(int index) async {
    final value = await AppDialogs.promptNumber(
      context,
      title: 'Jumlah label',
      initial: _items[index].copies.toDouble(),
    );
    if (value == null || !mounted) return;
    _queue.setCopies(index, value.round());
  }

  Future<Uint8List> _pdf() async {
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter/Inter-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Inter/Inter-Bold.ttf'),
    );
    return buildLabelPdf(
      items: _items,
      layout: _layout,
      options: _options,
      regular: regular,
      bold: bold,
    );
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_items.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await job();
    } catch (e) {
      if (mounted) {
        await AppDialogs.alert(
          context,
          title: 'Gagal membuat label',
          message: '$e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() => _run(() async {
    final saved = await saveFileAs(
      fileName: 'label-barang-${fileStamp()}.pdf',
      bytes: await _pdf(),
      extension: 'pdf',
      mimeType: 'application/pdf',
    );
    if (saved != null && mounted) {
      await AppDialogs.alert(context, title: 'Tersimpan', message: saved);
    }
  });

  /// Langsung ke printer nota (thermal) yang diatur di Kasir.
  Future<void> _printThermal() => _run(() async {
    await ref.read(labelPrinterProvider).print(_items, _layout, _options);
    if (mounted) {
      await AppDialogs.alert(
        context,
        title: 'Label dikirim ke printer',
        message: '$_labelCount label.',
      );
    }
  });

  /// Komputer: PDF dibuka di aplikasi bawaan (lalu Cetak dari sana).
  Future<void> _open() => _run(() async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'label-barang-${fileStamp()}.pdf'));
    await file.writeAsBytes(await _pdf());
    final command = Platform.isWindows
        ? 'explorer'
        : Platform.isMacOS
        ? 'open'
        : 'xdg-open';
    await Process.run(command, [file.path]);
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    ref.watch(labelQueueProvider);
    final printerReady =
        ref.watch(printerConfigProvider).value?.isReady ?? false;
    final pages = labelPageCount(_layout, _labelCount, startAt: _startAt);

    final list = AppCard(
      padding: EdgeInsets.zero,
      child: _items.isEmpty
          ? ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 220),
              child: const EmptyState(
                icon: CupertinoIcons.tag,
                title: 'Belum ada barang',
                message:
                    'Scan atau ketik barcode lalu Enter, atau cari nama '
                    'barang. Barcode kemasan (DUS) mencetak label kemasan.',
              ),
            )
          : Column(
              children: [
                for (final (i, item) in _items.indexed) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.md),
                      child: Container(height: 0.5, color: c.separator),
                    ),
                  _ItemRow(
                    item: item,
                    onMinus: () => _queue.setCopies(i, item.copies - 1),
                    onPlus: () => _queue.setCopies(i, item.copies + 1),
                    onEdit: () => _editCopies(i),
                    onRemove: () => _queue.removeAt(i),
                  ),
                ],
              ],
            ),
    );

    final settings = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InsetGroupedSection(
          header: 'Kertas',
          children: [
            InsetGroupedTile(
              title: 'Ukuran',
              value: _layout.name,
              onPressed: _pickLayout,
              showChevron: true,
            ),
            if (!_layout.isRoll)
              InsetGroupedTile(
                title: 'Mulai dari label ke-',
                subtitle:
                    'Untuk kertas stiker yang sebagian sudah terpakai '
                    '(1 = kiri atas, urut ke kanan).',
                trailing: SizedBox(
                  width: 64,
                  child: CupertinoTextField(
                    controller: _start,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        InsetGroupedSection(
          header: 'Isi label',
          children: [
            _switch('Nama barang', _showName, (v) => _showName = v),
            _switch('Harga', _showPrice, (v) => _showPrice = v),
            _switch('Nama toko', _showStore, (v) => _showStore = v),
            _switch(
              'Barcode pabrik (EAN) bila ada',
              _factory,
              (v) => _factory = v,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LabelView(
              layout: _layout,
              options: _options,
              item: _items.firstOrNull ?? _sample,
              border: Border.all(color: c.separator),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _items.isEmpty
              ? 'Contoh tampilan label.'
              : '$_labelCount label · $pages halaman',
          textAlign: TextAlign.center,
          style: AppTypography.footnote.copyWith(color: c.labelSecondary),
        ),
        if (_showPrice && ref.watch(storeScopeProvider) == null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Harga = harga default. Pilih toko di sidebar untuk harga toko.',
            textAlign: TextAlign.center,
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
        ],
      ],
    );

    final entry = WithScanButton(
      topOffset: 0,
      onScanned: _submitCode,
      field: Row(
        children: [
          Expanded(
            child: CupertinoTextField(
              controller: _code,
              focusNode: _codeFocus,
              autofocus: !Device.isTouch,
              placeholder: 'Scan / ketik barcode lalu Enter',
              prefix: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Icon(
                  CupertinoIcons.barcode,
                  size: 18,
                  color: c.labelSecondary,
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm + 2,
              ),
              decoration: BoxDecoration(
                color: c.fill,
                borderRadius: AppRadius.mdAll,
              ),
              onSubmitted: (_) => _submitCode(),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppButton(
            label: 'Cari',
            icon: CupertinoIcons.search,
            variant: AppButtonVariant.gray,
            onPressed: () => _search(initial: _code.text.trim()),
          ),
        ],
      ),
    );

    return LargeTitlePage(
      title: 'Cetak Label',
      subtitle: 'Label barcode & harga untuk ditempel di barang/rak',
      backLabel: 'Produk',
      onBack: () => context.go(AppRoutes.produk),
      actions: [
        if (_items.isNotEmpty)
          AppButton(
            label: 'Kosongkan',
            icon: CupertinoIcons.trash,
            variant: AppButtonVariant.plain,
            destructive: true,
            onPressed: _busy ? null : _queue.clear,
          ),
        if (printerReady)
          AppButton(
            label: 'Cetak ke Printer Nota',
            icon: CupertinoIcons.printer_fill,
            variant: AppButtonVariant.gray,
            onPressed: _items.isEmpty || _busy ? null : _printThermal,
          ),
        if (!Device.isAndroid)
          AppButton(
            label: 'Buka & Cetak',
            icon: CupertinoIcons.printer,
            loading: _busy,
            onPressed: _items.isEmpty ? null : _open,
          ),
        AppButton(
          label: 'Simpan PDF',
          icon: CupertinoIcons.square_arrow_down,
          variant: Device.isAndroid
              ? AppButtonVariant.filled
              : AppButtonVariant.gray,
          onPressed: _items.isEmpty || _busy ? null : _save,
        ),
      ],
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          entry,
          if (_codeError != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _codeError!,
              style: AppTypography.footnote.copyWith(color: c.danger),
            ),
          ],
        ],
      ),
      // Lebar layar ≥ 1100 (sidebar + 2 kolom): daftar & pengaturan
      // berdampingan. Sliver biasa (bukan `child`) supaya tidak diukur
      // tinggi intrinsiknya.
      slivers: [
        SliverToBoxAdapter(
          child: MediaQuery.sizeOf(context).width >= 1100
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: list),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 2, child: settings),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    list,
                    const SizedBox(height: AppSpacing.lg),
                    settings,
                  ],
                ),
        ),
      ],
    );
  }

  Widget _switch(String title, bool value, void Function(bool) set) =>
      InsetGroupedTile(
        title: title,
        trailing: CupertinoSwitch(
          value: value,
          activeTrackColor: context.colors.success,
          onChanged: (v) => setState(() => set(v)),
        ),
      );

  static const _sample = LabelItem(
    productId: 0,
    name: 'Contoh Barang 250 ml',
    code: 'BMM0000001',
    price: 12500,
  );
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.onMinus,
    required this.onPlus,
    required this.onEdit,
    required this.onRemove,
  });

  final LabelItem item;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.unitName == null
                      ? item.name
                      : '${item.name} (${item.unitName})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.subheadline.copyWith(
                    color: c.label,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${item.code} · ${Fmt.rupiah(item.price)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: c.labelSecondary,
                  ),
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: CupertinoIcons.minus,
            tooltip: 'Kurangi',
            onPressed: onMinus,
          ),
          Tooltip(
            message: 'Ketik jumlah label',
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(40, 36),
              onPressed: onEdit,
              child: Text(
                '${item.copies}',
                style: AppTypography.headline.copyWith(
                  color: c.label,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          AppIconButton(
            icon: CupertinoIcons.plus,
            tooltip: 'Tambah',
            onPressed: onPlus,
          ),
          AppIconButton(
            icon: CupertinoIcons.xmark_circle_fill,
            tooltip: 'Hapus',
            color: c.labelTertiary,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
