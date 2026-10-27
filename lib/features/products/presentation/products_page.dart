import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/barcode_scanner.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/option_picker.dart';
import '../../../core/widgets/pressable_scale.dart';
import '../../../core/widgets/state_views.dart';
import '../data/tag_repository.dart';
import '../domain/product.dart';
import '../domain/tag.dart';
import 'tag_chip.dart';
import 'product_export_dialog.dart';
import '../../labels/presentation/label_queue.dart';
import '../data/product_repository.dart';
import 'product_form_sheet.dart';
import 'product_providers.dart';
import '../../stores/presentation/store_scope.dart';
import '../../sync/data/terminal_repository.dart';
import '../../sync/domain/terminal.dart';

/// Master barang (khusus admin): cari, filter, urutkan, tambah, ubah, hapus.
class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});

  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  ProductFilter _filter = const ProductFilter();
  int _page = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _setFilter(ProductFilter f) => setState(() {
    _filter = f;
    _page = 0;
  });

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 200),
      () => _setFilter(_filter.copyWith(text: text)),
    );
  }

  Future<void> _pickTag() async {
    final tags = ref.read(tagsProvider).value ?? const <Tag>[];
    final current = tags.where((t) => t.id == _filter.tagId).firstOrNull;
    final pick = await showOptionPicker(
      context,
      title: 'Filter kategori',
      options: [for (final t in tags) t.name],
      selected: current?.name,
      clearLabel: 'Semua kategori',
    );
    if (pick == null) return;
    final id = tags.where((t) => t.name == pick.value).firstOrNull?.id;
    _setFilter(_filter.copyWith(tagId: () => id));
  }

  Future<void> _pickSort() async {
    final sort = await AppDialogs.actionSheet<ProductSort>(
      context,
      title: 'Urutkan',
      options: [
        for (final s in ProductSort.values)
          ActionSheetOption(
            label: s == _filter.sort ? '✓  ${s.label}' : s.label,
            value: s,
          ),
      ],
    );
    if (sort != null) _setFilter(_filter.copyWith(sort: sort));
  }

  bool get _filtered =>
      _filter.text.trim().isNotEmpty ||
      _filter.tagId != null ||
      _filter.lowStockOnly;

  Future<void> _printLabels(ProductFilter filter) async {
    if (_filtered) {
      final list = await ref
          .read(productRepositoryProvider)
          .allMatching(filter);
      final queue = ref.read(labelQueueProvider.notifier);
      for (final p in list) {
        queue.addProduct(p);
      }
    }
    if (mounted) context.go(AppRoutes.cetakLabel);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Stok & harga mengikuti toko yang dipilih di sidebar.
    final store = ref.watch(activeStoreProvider);
    final storeId = ref.watch(storeScopeProvider);
    final filter = _filter.copyWith(storeId: () => storeId);
    final count = ref.watch(productCountProvider(filter)).value;
    final page = ref.watch(productPageProvider((filter, _page)));
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    final tag = tags.where((t) => t.id == _filter.tagId).firstOrNull;

    return LargeTitlePage(
      title: 'Produk',
      subtitle: count == null
          ? null
          : '${Fmt.number(count)} barang · '
                '${storeId == null ? 'stok semua toko' : 'stok & harga ${store?.name ?? 'toko'}'}',
      actions: [
        AppButton(
          // Daftar sedang difilter: semua barang hasil filter masuk ke
          // daftar label.
          label: _filtered && count != null
              ? 'Cetak Label ($count)'
              : 'Cetak Label',
          icon: CupertinoIcons.tag,
          variant: AppButtonVariant.gray,
          onPressed: () => _printLabels(filter),
        ),
        AppButton(
          label: 'Input Tabel',
          icon: CupertinoIcons.table,
          variant: AppButtonVariant.gray,
          onPressed: () => context.go(AppRoutes.inputTabel),
        ),
        AppButton(
          label: 'Import',
          icon: CupertinoIcons.arrow_down_doc,
          variant: AppButtonVariant.gray,
          onPressed: () => context.go(AppRoutes.importProduk),
        ),
        AppButton(
          label: 'Export',
          icon: CupertinoIcons.square_arrow_up,
          variant: AppButtonVariant.gray,
          onPressed: () =>
              showProductExportDialog(context, currentFilter: filter),
        ),
        AppButton(
          label: 'Tambah',
          icon: CupertinoIcons.add,
          onPressed: () => showProductFormSheet(context),
        ),
      ],
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ref.watch(terminalProvider).value?.mode == TerminalMode.client)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                'Komputer cabang: data barang dari server pusat dan hanya '
                'bisa diubah di komputer server.',
                style: AppTypography.footnote.copyWith(color: c.warning),
              ),
            ),
          // HP/tablet: cari barang dengan memotret barcodenya.
          WithScanButton(
            topOffset: 0,
            size: 40,
            onScanned: (code) {
              _search.text = code;
              _onSearch(code);
            },
            field: SizedBox(
              height: 40,
              child: CupertinoSearchTextField(
                controller: _search,
                placeholder: 'Cari nama atau barcode',
                style: AppTypography.body.copyWith(color: c.label),
                onChanged: _onSearch,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CupertinoSlidingSegmentedControl<ProductStatusFilter>(
                groupValue: _filter.status,
                padding: const EdgeInsets.all(2),
                onValueChanged: (v) {
                  if (v != null) _setFilter(_filter.copyWith(status: v));
                },
                children: {
                  for (final s in ProductStatusFilter.values)
                    s: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Text(s.label, style: AppTypography.footnote),
                    ),
                },
              ),
              if (tags.isNotEmpty || tag != null)
                _FilterChip(
                  icon: CupertinoIcons.square_grid_2x2,
                  label: tag?.name ?? 'Semua kategori',
                  active: tag != null,
                  activeColor: tag?.color.color,
                  onTap: _pickTag,
                ),
              _FilterChip(
                icon: CupertinoIcons.exclamationmark_triangle,
                label: 'Stok menipis',
                active: _filter.lowStockOnly,
                activeColor: c.warning,
                onTap: () => _setFilter(
                  _filter.copyWith(lowStockOnly: !_filter.lowStockOnly),
                ),
              ),
              _FilterChip(
                icon: CupertinoIcons.arrow_up_arrow_down,
                label: _filter.sort.label,
                active: false,
                onTap: _pickSort,
              ),
            ],
          ),
        ],
      ),
      slivers: [
        SliverToBoxAdapter(
          child: page.when(
            loading: () => const SizedBox(height: 240, child: LoadingState()),
            error: (e, _) => ErrorBanner(message: 'Gagal memuat barang: $e'),
            data: (list) => list.isEmpty
                ? _Empty(filter: filter)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InsetGroupedSection(
                        dividerIndent: 66,
                        children: [
                          for (final p in list)
                            _ProductTile(
                              product: p,
                              onTap: () =>
                                  showProductFormSheet(context, existing: p),
                            ),
                        ],
                      ),
                      if (count != null && count > productPageSize)
                        _Pager(
                          page: _page,
                          total: count,
                          onChanged: (p) => setState(() => _page = p),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.activeColor,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = activeColor ?? c.accent;
    return PressableScale(
      onPressed: onTap,
      pressedScale: 0.95,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.14) : c.fill,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: active ? color : c.labelSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.footnote.copyWith(
                color: active ? color : c.label,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = product;
    final sub = [p.code, if (p.barcode != null) p.barcode!].join(' · ');

    return InsetGroupedTile(
      leading: Opacity(
        opacity: p.isActive ? 1 : 0.45,
        // Warna kategori pertama, supaya jenis barang terlihat sekilas.
        child: _Initials(
          name: p.name,
          seed: p.name,
          tagColor: p.tags.firstOrNull?.color,
        ),
      ),
      title: p.name,
      subtitle: sub,
      below: p.tags.isEmpty ? null : TagChips(tags: p.tags),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Fmt.rupiah(p.sellingPrice),
            style: AppTypography.subheadline.copyWith(
              color: c.label,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!p.isActive)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    'Nonaktif',
                    style: AppTypography.caption.copyWith(
                      color: c.labelSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (p.isLowStock && p.isActive)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(
                    CupertinoIcons.exclamationmark_triangle_fill,
                    size: 12,
                    color: c.warning,
                  ),
                ),
              Text(
                'Stok ${Fmt.number(p.stock)} ${p.unitName ?? ''}'.trim(),
                style: AppTypography.footnote.copyWith(
                  color: p.isLowStock && p.isActive
                      ? c.warning
                      : c.labelSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
      showChevron: true,
      onPressed: onTap,
    );
  }
}

/// Kotak membulat berisi inisial nama barang, warnanya stabil per kategori.
class _Initials extends StatelessWidget {
  const _Initials({required this.name, required this.seed, this.tagColor});

  final String name;
  final String seed;

  /// Warna tag pertama barang: kotak diisi penuh warna itu. `null` = warna
  /// lembut dipilih dari [seed].
  final TagColor? tagColor;

  static const _palette = [
    Color(0xFF007AFF),
    Color(0xFF34C759),
    Color(0xFFFF9500),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
    Color(0xFF5AC8FA),
    Color(0xFF5856D6),
    Color(0xFFA2845E),
  ];

  @override
  Widget build(BuildContext context) {
    final words = name.trim().split(RegExp(r'\s+'));
    final initials = words
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0])
        .join()
        .toUpperCase();
    final tag = tagColor;
    final color =
        tag?.color ??
        _palette[seed.codeUnits.fold<int>(0, (a, b) => a + b) %
            _palette.length];
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tag == null ? color.withValues(alpha: 0.15) : color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        initials,
        style: AppTypography.headline.copyWith(
          color: tag?.onColor ?? color,
          fontSize: 15,
        ),
      ),
    );
  }
}

class _Pager extends StatelessWidget {
  const _Pager({
    required this.page,
    required this.total,
    required this.onChanged,
  });

  final int page;
  final int total;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final last = (total - 1) ~/ productPageSize;
    final from = page * productPageSize + 1;
    final to = ((page + 1) * productPageSize).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Row(
        children: [
          Text(
            '${Fmt.number(from)}–${Fmt.number(to)} dari ${Fmt.number(total)}',
            style: AppTypography.footnote.copyWith(color: c.labelSecondary),
          ),
          const Spacer(),
          AppButton(
            label: 'Sebelumnya',
            icon: CupertinoIcons.chevron_left,
            variant: AppButtonVariant.gray,
            size: AppButtonSize.small,
            onPressed: page == 0 ? null : () => onChanged(page - 1),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppButton(
            label: 'Berikutnya',
            icon: CupertinoIcons.chevron_right,
            variant: AppButtonVariant.gray,
            size: AppButtonSize.small,
            onPressed: page >= last ? null : () => onChanged(page + 1),
          ),
        ],
      ),
    );
  }
}

/// Kosong: tampilkan saran nama mirip jika sedang mencari, atau ajakan
/// menambah barang.
class _Empty extends ConsumerWidget {
  const _Empty({required this.filter});

  final ProductFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searching = filter.text.trim().isNotEmpty;
    if (!searching) {
      return Container(
        constraints: const BoxConstraints(minHeight: 320),
        alignment: Alignment.center,
        child: EmptyState(
          icon: CupertinoIcons.cube_box,
          title: 'Tidak ada barang',
          message: filter.copyWith(storeId: () => null) == const ProductFilter()
              ? 'Tambah barang satu per satu atau import dari file Excel.'
              : 'Tidak ada barang yang cocok dengan filter ini.',
        ),
      );
    }
    final suggestions =
        ref.watch(productSuggestionsProvider(filter.text)).value ??
        const <Product>[];
    if (suggestions.isEmpty) {
      return Container(
        constraints: const BoxConstraints(minHeight: 320),
        alignment: Alignment.center,
        child: EmptyState(
          icon: CupertinoIcons.search,
          title: 'Barang tidak ditemukan',
          message: 'Tidak ada barang yang cocok dengan "${filter.text}".',
        ),
      );
    }
    return InsetGroupedSection(
      header: 'Mungkin maksud Anda',
      footer:
          'Tidak ada yang cocok persis dengan "${filter.text}". '
          'Saran berdasarkan nama yang mirip.',
      dividerIndent: 66,
      children: [
        for (final p in suggestions)
          _ProductTile(
            product: p,
            onTap: () => showProductFormSheet(context, existing: p),
          ),
      ],
    );
  }
}
