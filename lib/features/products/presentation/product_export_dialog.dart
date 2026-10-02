import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/save_file.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/state_views.dart';
import '../data/product_file_io.dart';
import '../data/product_repository.dart';
import '../domain/product.dart';

/// Popup export barang ke Excel/CSV, beserta unduh template import.
Future<void> showProductExportDialog(
  BuildContext context, {
  required ProductFilter currentFilter,
}) {
  return AppDialogs.popup<void>(
    context,
    title: 'Export Barang',
    maxWidth: 460,
    builder: (_) => _ExportForm(currentFilter: currentFilter),
  );
}

Future<String?> saveBytes(
  String fileName,
  Uint8List bytes,
  ProductFileFormat format,
) => saveFileAs(
  fileName: fileName,
  bytes: bytes,
  extension: format.extension,
  mimeType: format == ProductFileFormat.xlsx ? xlsxMime : 'text/csv',
);

/// Unduh template import kosong (dipakai di popup export dan halaman import).
Future<void> downloadImportTemplate(BuildContext context) async {
  final path = await saveBytes(
    'template-import-barang.xlsx',
    productTemplateXlsx(),
    ProductFileFormat.xlsx,
  );
  if (path != null && context.mounted) {
    await AppDialogs.alert(
      context,
      title: 'Template tersimpan',
      message:
          '$path\n\nIsi sheet "Barang", lalu import lewat Produk › Import.',
    );
  }
}

class _ExportForm extends ConsumerStatefulWidget {
  const _ExportForm({required this.currentFilter});

  final ProductFilter currentFilter;

  @override
  ConsumerState<_ExportForm> createState() => _ExportFormState();
}

class _ExportFormState extends ConsumerState<_ExportForm> {
  ProductFileFormat _format = ProductFileFormat.xlsx;
  bool _onlyFiltered = false;
  bool _busy = false;
  String? _error;

  /// Ada pencarian/filter aktif (urutan saja tidak dihitung).
  bool get _hasFilter =>
      widget.currentFilter.copyWith(
        sort: ProductSort.name,
        storeId: () => null,
      ) !=
      const ProductFilter();

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(productRepositoryProvider);
      final products = await repo.allMatching(
        _onlyFiltered
            ? widget.currentFilter
            : ProductFilter(
                status: ProductStatusFilter.all,
                storeId: widget.currentFilter.storeId,
              ),
      );
      final bytes = _format == ProductFileFormat.xlsx
          ? exportProductsXlsx(products)
          : exportProductsCsv(products);
      final path = await saveBytes(
        'barang-${fileStamp()}.${_format.extension}',
        bytes,
        _format,
      );
      if (path == null || !mounted) return;
      Navigator.pop(context);
      await AppDialogs.alert(
        context,
        title: '${Fmt.number(products.length)} barang diexport',
        message: path,
      );
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Gagal export: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
          InsetGroupedSection(
            header: 'Format',
            children: [
              for (final f in ProductFileFormat.values)
                InsetGroupedTile(
                  title: f.label,
                  subtitle: f == ProductFileFormat.xlsx
                      ? 'Disarankan, langsung terbuka di Excel'
                      : 'Teks sederhana, bisa dibuka aplikasi apa pun',
                  trailing: _format == f
                      ? Icon(CupertinoIcons.checkmark_alt, color: c.accent)
                      : null,
                  showChevron: false,
                  onPressed: () => setState(() => _format = f),
                ),
            ],
          ),
          if (_hasFilter) ...[
            const SizedBox(height: AppSpacing.md),
            InsetGroupedSection(
              header: 'Barang',
              children: [
                InsetGroupedTile(
                  title: 'Semua barang',
                  subtitle: 'Termasuk yang nonaktif',
                  trailing: !_onlyFiltered
                      ? Icon(CupertinoIcons.checkmark_alt, color: c.accent)
                      : null,
                  showChevron: false,
                  onPressed: () => setState(() => _onlyFiltered = false),
                ),
                InsetGroupedTile(
                  title: 'Sesuai filter saat ini',
                  subtitle: 'Hasil pencarian/filter di halaman Produk',
                  trailing: _onlyFiltered
                      ? Icon(CupertinoIcons.checkmark_alt, color: c.accent)
                      : null,
                  showChevron: false,
                  onPressed: () => setState(() => _onlyFiltered = true),
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Export',
            icon: CupertinoIcons.square_arrow_up,
            size: AppButtonSize.large,
            expand: true,
            loading: _busy,
            onPressed: _export,
          ),
          const SizedBox(height: AppSpacing.xs),
          AppButton(
            label: 'Unduh template import kosong',
            icon: CupertinoIcons.doc,
            variant: AppButtonVariant.plain,
            expand: true,
            onPressed: _busy ? null : () => downloadImportTemplate(context),
          ),
          Text(
            'File export memakai kolom yang sama dengan template, jadi bisa '
            'diedit di Excel lalu di-import kembali.',
            textAlign: TextAlign.center,
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
        ],
      ),
    );
  }
}
