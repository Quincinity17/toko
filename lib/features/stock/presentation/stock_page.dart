import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_providers.dart';
import '../../stores/presentation/store_scope.dart';
import 'stock_adjust_dialog.dart';

/// Halaman Stok (admin & supervisor): stok barang di toko yang dipakai, lalu
/// sesuaikan per barang (barang masuk, keluar, atau stok opname).
class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

enum _StockView { all, low }

class _StockPageState extends ConsumerState<StockPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _text = '';
  _StockView _view = _StockView.all;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 200),
      () => setState(() => _text = text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final storeId = ref.watch(storeScopeProvider);
    final store = ref.watch(activeStoreProvider);

    if (storeId == null) {
      return LargeTitlePage(
        title: 'Stok',
        child: Container(
          constraints: const BoxConstraints(minHeight: 360),
          alignment: Alignment.center,
          child: EmptyState(
            icon: CupertinoIcons.building_2_fill,
            title: 'Pilih toko dulu',
            message: 'Stok dicatat per toko. Pilih toko yang ingin diatur.',
            actionLabel: 'Pilih Toko',
            onAction: () => pickStoreScope(context, ref, allowAll: false),
          ),
        ),
      );
    }

    final filter = ProductFilter(
      text: _text,
      storeId: storeId,
      lowStockOnly: _view == _StockView.low,
      sort: _view == _StockView.low ? ProductSort.stockLow : ProductSort.name,
    );
    final count = ref.watch(productCountProvider(filter)).value;
    final page = ref.watch(productPageProvider((filter, 0)));

    return LargeTitlePage(
      title: 'Stok',
      subtitle: store?.name,
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 40,
            child: CupertinoSearchTextField(
              controller: _search,
              placeholder: 'Cari nama, kode, atau barcode',
              style: AppTypography.body.copyWith(color: c.label),
              onChanged: _onSearch,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: CupertinoSlidingSegmentedControl<_StockView>(
              groupValue: _view,
              padding: const EdgeInsets.all(2),
              onValueChanged: (v) {
                if (v != null) setState(() => _view = v);
              },
              children: {
                for (final (v, label) in [
                  (_StockView.all, 'Semua barang'),
                  (_StockView.low, 'Stok menipis'),
                ])
                  v: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(label, style: AppTypography.footnote),
                  ),
              },
            ),
          ),
        ],
      ),
      slivers: [
        SliverToBoxAdapter(
          child: page.when(
            loading: () => const SizedBox(height: 240, child: LoadingState()),
            error: (e, _) => ErrorBanner(message: 'Gagal memuat stok: $e'),
            data: (list) => list.isEmpty
                ? Container(
                    constraints: const BoxConstraints(minHeight: 320),
                    alignment: Alignment.center,
                    child: EmptyState(
                      icon: _view == _StockView.low
                          ? CupertinoIcons.checkmark_seal
                          : CupertinoIcons.archivebox,
                      title: _view == _StockView.low
                          ? 'Tidak ada stok menipis'
                          : 'Barang tidak ditemukan',
                    ),
                  )
                : InsetGroupedSection(
                    footer: count != null && count > list.length
                        ? 'Menampilkan ${list.length} dari '
                              '${Fmt.number(count)} barang. Gunakan pencarian '
                              'untuk barang lainnya.'
                        : 'Klik barang untuk menambah, mengurangi, atau '
                              'menghitung ulang stok.',
                    children: [
                      for (final p in list)
                        _StockTile(
                          product: p,
                          onTap: () => showStockAdjustDialog(
                            context,
                            product: p,
                            storeId: storeId,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = product;
    final low = p.isLowStock;
    return InsetGroupedTile(
      title: p.name,
      subtitle: [
        p.code,
        if (p.minStock > 0) 'min. ${Fmt.number(p.minStock)}',
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (low)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                size: 13,
                color: c.warning,
              ),
            ),
          Text(
            '${Fmt.number(p.stock)} ${p.unitName ?? ''}'.trim(),
            style: AppTypography.headline.copyWith(
              color: low ? c.warning : c.label,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
      showChevron: true,
      onPressed: onTap,
    );
  }
}
