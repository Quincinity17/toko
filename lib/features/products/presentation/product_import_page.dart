import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/option_picker.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/presentation/auth_controller.dart';
import '../data/product_file_io.dart';
import '../data/product_import_service.dart';
import '../domain/product_import.dart';
import 'product_export_dialog.dart';
import '../../stores/data/store_repository.dart';
import '../../stores/domain/store.dart';
import '../../stores/presentation/store_scope.dart';

enum _Step { pick, map, review, running, done }

/// Membuka dialog pilih file dan mengembalikan (isi, nama file), atau `null`
/// jika batal. Berupa provider agar bisa diganti di tes.
final pickImportFileProvider =
    Provider<Future<(Uint8List, String)?> Function()>(
      (ref) => () async {
        final file = await FilePicker.pickFile(
          dialogTitle: 'Pilih file barang',
          type: FileType.custom,
          allowedExtensions: const ['xlsx', 'csv'],
        );
        if (file == null) return null;
        return (await file.readAsBytes(), file.name);
      },
    );

/// Produk › Import: pilih file → cocokkan kolom → periksa → import → hasil.
class ProductImportPage extends ConsumerStatefulWidget {
  const ProductImportPage({super.key});

  @override
  ConsumerState<ProductImportPage> createState() => _ProductImportPageState();
}

class _ProductImportPageState extends ConsumerState<ProductImportPage> {
  _Step _step = _Step.pick;
  bool _busy = false;
  String? _error;

  String? _fileName;
  ImportTable? _table;
  ImportMapping _mapping = {};
  List<ImportRow> _rows = const [];
  ExistingProductAction _action = ExistingProductAction.skip;

  /// Toko tujuan kolom Stok (dipilih di langkah Periksa).
  int? _stockStoreId;

  List<Store> get _activeStores =>
      (ref.read(storesProvider).value ?? const <Store>[])
          .where((s) => s.isActive)
          .toList();

  /// Toko tujuan stok: pilihan user, toko yang sedang dipakai, atau satu-satunya
  /// toko aktif.
  int? get _stockStore {
    if (_stockStoreId != null) return _stockStoreId;
    final scope = ref.read(storeScopeProvider);
    if (scope != null) return scope;
    final stores = _activeStores;
    return stores.length == 1 ? stores.first.id : null;
  }

  Future<void> _pickStockStore() async {
    final stores = _activeStores;
    final current = stores.where((s) => s.id == _stockStore).firstOrNull;
    final pick = await showOptionPicker(
      context,
      title: 'Stok masuk ke toko',
      options: [for (final s in stores) s.name],
      selected: current?.name,
    );
    final name = pick?.value;
    if (name == null) return;
    setState(() => _stockStoreId = stores.firstWhere((s) => s.name == name).id);
  }

  (int, int) _progress = (0, 0);
  ImportResult? _result;

  Future<void> _pickFile() async {
    setState(() => _error = null);
    final picked = await ref.read(pickImportFileProvider)();
    if (picked == null) return;
    final (bytes, name) = picked;
    setState(() => _busy = true);
    try {
      final table = await readProductFile(bytes, name);
      setState(() {
        _fileName = name;
        _table = table;
        _mapping = guessMapping(table.headers);
        _step = _Step.map;
      });
    } on ProductFileFailure catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = 'File tidak bisa dibaca: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<ProductField> get _missingRequired => [
    for (final f in ProductField.values)
      if (f.required && _mapping[f] == null) f,
  ];

  Future<void> _check() async {
    setState(() => _busy = true);
    final existing = await ref
        .read(productImportServiceProvider)
        .existingIndex();
    setState(() {
      _rows = validateImport(_table!, _mapping, existing);
      _busy = false;
      _step = _Step.review;
    });
  }

  Future<void> _run() async {
    setState(() {
      _step = _Step.running;
      _progress = (0, _rows.where((r) => r.isValid).length);
    });
    try {
      final result = await ref
          .read(productImportServiceProvider)
          .run(
            actor: ref.read(authControllerProvider)!,
            rows: _rows,
            existingAction: _action,
            stockStoreId: _stockStore,
            onProgress: (done, total) {
              if (mounted) setState(() => _progress = (done, total));
            },
          );
      setState(() {
        _result = result;
        _step = _Step.done;
      });
    } on Object catch (e) {
      setState(() {
        _error = 'Import dibatalkan, tidak ada data yang tersimpan. ($e)';
        _step = _Step.review;
      });
    }
  }

  void _restart() => setState(() {
    _step = _Step.pick;
    _table = null;
    _rows = const [];
    _result = null;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    // Daftar toko untuk pilihan tujuan stok.
    ref.watch(storesProvider);
    ref.watch(storeScopeProvider);
    return LargeTitlePage(
      title: 'Import Barang',
      backLabel: 'Produk',
      onBack: _step == _Step.running
          ? null
          : () => context.go(AppRoutes.produk),
      bottom: _StepIndicator(step: _step),
      slivers: [
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    ErrorBanner(message: _error!),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  switch (_step) {
                    _Step.pick => _PickStep(
                      busy: _busy,
                      onPick: _pickFile,
                      onTemplate: () => downloadImportTemplate(context),
                    ),
                    _Step.map => _MapStep(
                      fileName: _fileName!,
                      table: _table!,
                      mapping: _mapping,
                      missing: _missingRequired,
                      busy: _busy,
                      onChanged: (m) => setState(() => _mapping = m),
                      onBack: _restart,
                      onNext: _check,
                    ),
                    _Step.review => _ReviewStep(
                      rows: _rows,
                      hasStock: _mapping[ProductField.stock] != null,
                      stockStoreName: _activeStores
                          .where((s) => s.id == _stockStore)
                          .firstOrNull
                          ?.name,
                      onPickStockStore: _pickStockStore,
                      action: _action,
                      onAction: (a) => setState(() => _action = a),
                      onBack: () => setState(() => _step = _Step.map),
                      onRun: _run,
                    ),
                    _Step.running => _RunningStep(progress: _progress),
                    _Step.done => _DoneStep(
                      result: _result!,
                      onAgain: _restart,
                      onShow: () => context.go(AppRoutes.produk),
                    ),
                  },
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const labels = ['Pilih file', 'Cocokkan kolom', 'Periksa', 'Selesai'];
    final current = switch (step) {
      _Step.pick => 0,
      _Step.map => 1,
      _Step.review || _Step.running => 2,
      _Step.done => 3,
    };
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Container(
              width: 24,
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: c.separator,
            ),
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= current ? c.accent : c.fill,
            ),
            child: i < current
                ? const Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 13,
                    color: CupertinoColors.white,
                  )
                : Text(
                    '${i + 1}',
                    style: AppTypography.caption.copyWith(
                      color: i <= current
                          ? CupertinoColors.white
                          : c.labelSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          const SizedBox(width: 6),
          Text(
            labels[i],
            style: AppTypography.footnote.copyWith(
              color: i == current ? c.label : c.labelSecondary,
              fontWeight: i == current ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ],
    );
  }
}

class _PickStep extends StatelessWidget {
  const _PickStep({
    required this.busy,
    required this.onPick,
    required this.onTemplate,
  });

  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onTemplate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            children: [
              Icon(CupertinoIcons.doc_on_doc_fill, size: 56, color: c.accent),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Pilih file Excel atau CSV',
                style: AppTypography.title3.copyWith(color: c.label),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Bisa file export iPOS, file export aplikasi ini, atau template '
                'yang sudah diisi. Kolom dicocokkan otomatis dan bisa diubah.',
                textAlign: TextAlign.center,
                style: AppTypography.subheadline.copyWith(
                  color: c.labelSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Pilih File',
                icon: CupertinoIcons.folder_open,
                size: AppButtonSize.large,
                loading: busy,
                onPressed: onPick,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        InsetGroupedSection(
          header: 'Tips',
          children: [
            InsetGroupedTile(
              leading: TileIcon(icon: CupertinoIcons.doc, color: c.success),
              title: 'Unduh template kosong',
              subtitle: 'Isi di Excel, lalu import di sini',
              onPressed: onTemplate,
            ),
            const InsetGroupedTile(
              title: 'Dari iPOS',
              subtitle:
                  'Export daftar item ke Excel. File .xls lama: buka di Excel, '
                  'lalu Simpan Sebagai .xlsx.',
            ),
            const InsetGroupedTile(
              title: 'Kode yang sudah ada',
              subtitle:
                  'Bisa dilewati, ditimpa, atau hanya diperbarui stok & '
                  'harganya. Dipilih di langkah Periksa.',
            ),
          ],
        ),
      ],
    );
  }
}

class _MapStep extends StatelessWidget {
  const _MapStep({
    required this.fileName,
    required this.table,
    required this.mapping,
    required this.missing,
    required this.busy,
    required this.onChanged,
    required this.onBack,
    required this.onNext,
  });

  final String fileName;
  final ImportTable table;
  final ImportMapping mapping;
  final List<ProductField> missing;
  final bool busy;
  final ValueChanged<ImportMapping> onChanged;
  final VoidCallback onBack;
  final VoidCallback onNext;

  String _columnLabel(int i) {
    final h = table.headers[i];
    return h.isEmpty ? 'Kolom ${i + 1}' : h;
  }

  Future<void> _pick(BuildContext context, ProductField field) async {
    final labels = [
      for (var i = 0; i < table.headers.length; i++) _columnLabel(i),
    ];
    final current = mapping[field];
    final pick = await showOptionPicker(
      context,
      title: 'Kolom untuk "${field.label}"',
      options: labels,
      selected: current == null ? null : labels[current],
      clearLabel: field.required ? null : 'Tidak dipakai',
    );
    if (pick == null) return;
    final index = pick.value == null ? null : labels.indexOf(pick.value!);
    onChanged({...mapping, field: index});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sample = table.rows.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(CupertinoIcons.doc_text_fill, color: c.success),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '$fileName · ${Fmt.number(table.rows.length)} baris · '
                  '${table.headers.length} kolom',
                  style: AppTypography.subheadline.copyWith(color: c.label),
                ),
              ),
              AppButton(
                label: 'Ganti file',
                variant: AppButtonVariant.plain,
                size: AppButtonSize.small,
                onPressed: onBack,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        InsetGroupedSection(
          header: 'Cocokkan kolom',
          footer:
              'Ditebak otomatis dari judul kolom file. Ketuk untuk mengubah. '
              'Contoh nilai diambil dari baris pertama.',
          children: [
            for (final f in ProductField.values)
              InsetGroupedTile(
                title: f.required ? '${f.label} *' : f.label,
                subtitle: mapping[f] == null
                    ? (f.required ? 'Wajib dipilih' : null)
                    : 'Contoh: ${mapping[f]! < sample.length ? sample[mapping[f]!] : ''}',
                value: mapping[f] == null
                    ? 'Tidak dipakai'
                    : _columnLabel(mapping[f]!),
                destructive: f.required && mapping[f] == null,
                onPressed: () => _pick(context, f),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _Preview(table: table, mapping: mapping),
        const SizedBox(height: AppSpacing.xl),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ErrorBanner(
              message:
                  'Pilih kolom untuk: ${missing.map((f) => f.label).join(', ')}.',
            ),
          ),
        AppButton(
          label: 'Periksa Data',
          icon: CupertinoIcons.checkmark_shield,
          size: AppButtonSize.large,
          expand: true,
          loading: busy,
          onPressed: missing.isEmpty ? onNext : null,
        ),
      ],
    );
  }
}

/// Pratinjau 5 baris pertama sesuai kolom yang dipilih.
class _Preview extends StatelessWidget {
  const _Preview({required this.table, required this.mapping});

  final ImportTable table;
  final ImportMapping mapping;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fields = [
      for (final f in ProductField.values)
        if (mapping[f] != null) f,
    ];
    final count = table.rows.length < 5 ? table.rows.length : 5;
    final head = AppTypography.caption.copyWith(
      color: c.labelSecondary,
      fontWeight: FontWeight.w600,
    );
    final body = AppTypography.footnote.copyWith(color: c.label);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Text(
            'PRATINJAU',
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                TableRow(
                  children: [
                    for (final f in fields)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 20, 8),
                        child: Text(f.label.toUpperCase(), style: head),
                      ),
                  ],
                ),
                for (var r = 0; r < count; r++)
                  TableRow(
                    children: [
                      for (final f in fields)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 4, 20, 4),
                          child: Text(
                            table.cell(r, mapping[f]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: body,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.rows,
    required this.hasStock,
    required this.stockStoreName,
    required this.onPickStockStore,
    required this.action,
    required this.onAction,
    required this.onBack,
    required this.onRun,
  });

  final List<ImportRow> rows;

  /// File punya kolom Stok, jadi perlu toko tujuan.
  final bool hasStock;
  final String? stockStoreName;
  final VoidCallback onPickStockStore;
  final ExistingProductAction action;
  final ValueChanged<ExistingProductAction> onAction;
  final VoidCallback onBack;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final newCount = rows.where((r) => r.isNew).length;
    final existingCount = rows.where((r) => r.isExisting).length;
    final errors = rows.where((r) => !r.isValid).toList();
    final toImport =
        newCount + (action == ExistingProductAction.skip ? 0 : existingCount);

    Widget stat(String label, int value, Color color, IconData icon) =>
        Expanded(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  Fmt.number(value),
                  style: AppTypography.title1.copyWith(color: c.label),
                ),
                Text(
                  label,
                  style: AppTypography.subheadline.copyWith(
                    color: c.labelSecondary,
                  ),
                ),
              ],
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            stat(
              'Barang baru',
              newCount,
              c.success,
              CupertinoIcons.plus_circle_fill,
            ),
            const SizedBox(width: AppSpacing.md),
            stat(
              'Kode sudah ada',
              existingCount,
              c.accent,
              CupertinoIcons.arrow_2_circlepath_circle_fill,
            ),
            const SizedBox(width: AppSpacing.md),
            stat(
              'Baris error',
              errors.length,
              errors.isEmpty ? c.labelTertiary : c.danger,
              CupertinoIcons.exclamationmark_circle_fill,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        InsetGroupedSection(
          header: 'Toko',
          footer: hasStock
              ? 'Kolom Stok mengisi stok toko ini. Harga jual di file menjadi '
                    'harga default semua toko.'
              : 'File tanpa kolom Stok: stok tidak berubah. Harga jual di '
                    'file menjadi harga default semua toko.',
          children: [
            if (hasStock)
              InsetGroupedTile(
                title: 'Stok masuk ke toko',
                value: stockStoreName ?? 'Pilih toko',
                onPressed: onPickStockStore,
              ),
            if (!hasStock)
              const InsetGroupedTile(
                title: 'Stok',
                value: 'Tidak diubah',
                showChevron: false,
              ),
          ],
        ),
        if (existingCount > 0) ...[
          const SizedBox(height: AppSpacing.xl),
          InsetGroupedSection(
            header: 'Untuk $existingCount barang yang kodenya sudah ada',
            children: [
              for (final a in ExistingProductAction.values)
                InsetGroupedTile(
                  title: a.label,
                  subtitle: a.description,
                  trailing: action == a
                      ? Icon(CupertinoIcons.checkmark_alt, color: c.accent)
                      : null,
                  showChevron: false,
                  onPressed: () => onAction(a),
                ),
            ],
          ),
        ],
        if (errors.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          InsetGroupedSection(
            header: 'Baris bermasalah (tidak akan di-import)',
            footer: errors.length > 200
                ? 'Menampilkan 200 dari ${Fmt.number(errors.length)} baris. '
                      'Perbaiki di file lalu import ulang.'
                : 'Perbaiki di file lalu import ulang, atau lanjutkan tanpa '
                      'baris ini.',
            children: [
              for (final r in errors.take(200))
                InsetGroupedTile(
                  leading: Text(
                    'Baris ${r.rowNumber}',
                    style: AppTypography.footnote.copyWith(
                      color: c.danger,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  title: r.errors.join(' '),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            AppButton(
              label: 'Ubah Kolom',
              icon: CupertinoIcons.chevron_left,
              variant: AppButtonVariant.gray,
              onPressed: onBack,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: toImport == 0
                    ? 'Tidak ada yang di-import'
                    : 'Import ${Fmt.number(toImport)} barang',
                icon: CupertinoIcons.arrow_down_doc_fill,
                size: AppButtonSize.large,
                expand: true,
                onPressed: toImport == 0 || (hasStock && stockStoreName == null)
                    ? null
                    : onRun,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RunningStep extends StatelessWidget {
  const _RunningStep({required this.progress});

  final (int, int) progress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (done, total) = progress;
    final ratio = total == 0 ? 0.0 : done / total;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        children: [
          const CupertinoActivityIndicator(radius: 14),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Mengimport ${Fmt.number(done)} dari ${Fmt.number(total)} barang…',
            style: AppTypography.headline.copyWith(color: c.label),
          ),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(height: 8, color: c.fill),
                AnimatedFractionallySizedBox(
                  duration: AppDurations.medium,
                  curve: SpringCurve.smooth,
                  widthFactor: ratio,
                  child: Container(height: 8, color: c.accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Jangan tutup aplikasi. Jika gagal, tidak ada data yang tersimpan.',
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
        ],
      ),
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({
    required this.result,
    required this.onAgain,
    required this.onShow,
  });

  final ImportResult result;
  final VoidCallback onAgain;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.4, end: 1),
                duration: AppDurations.slow,
                curve: SpringCurve.bouncy,
                builder: (_, s, child) =>
                    Transform.scale(scale: s, child: child),
                child: Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  size: 64,
                  color: c.success,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Import selesai',
                style: AppTypography.title2.copyWith(color: c.label),
              ),
              Text(
                '${Fmt.number(result.succeeded)} barang tersimpan',
                style: AppTypography.subheadline.copyWith(
                  color: c.labelSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        InsetGroupedSection(
          header: 'Hasil',
          children: [
            InsetGroupedTile(
              title: 'Barang baru ditambahkan',
              value: Fmt.number(result.inserted),
            ),
            InsetGroupedTile(
              title: 'Barang lama diperbarui',
              value: Fmt.number(result.updated),
            ),
            InsetGroupedTile(
              title: 'Dilewati (kode sudah ada)',
              value: Fmt.number(result.skipped),
            ),
            InsetGroupedTile(
              title: 'Gagal (baris error)',
              value: Fmt.number(result.failed.length),
              destructive: result.failed.isNotEmpty,
            ),
            if (result.newCategories > 0 || result.newUnits > 0)
              InsetGroupedTile(
                title: 'Kategori / satuan baru',
                value: '${result.newCategories} / ${result.newUnits}',
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          children: [
            AppButton(
              label: 'Import File Lain',
              variant: AppButtonVariant.gray,
              onPressed: onAgain,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: 'Lihat Produk',
                size: AppButtonSize.large,
                expand: true,
                onPressed: onShow,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
