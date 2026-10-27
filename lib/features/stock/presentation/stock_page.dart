import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/barcode_scanner.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/inset_grouped_list.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/state_views.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_providers.dart';
import '../../stores/presentation/store_scope.dart';
import '../data/stock_repository.dart';
import 'stock_adjust_dialog.dart';
import 'stock_alert_list.dart';

/// Halaman Stok (admin & supervisor): stok barang di toko yang dipakai, lalu
/// sesuaikan per barang (barang masuk, keluar, atau stok opname).
class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});

  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

enum _StockView { all, alerts }

class _StockPageState extends ConsumerState<StockPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _text = '';
  _StockView _view = _StockView.all;

  @override
  void initState() {
    super.initState();
    // Dari Dashboard (kartu Peringatan stok): langsung ke tab Peringatan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final view = GoRouterState.of(context).uri.queryParameters['view'];
      if (view == 'peringatan') setState(() => _view = _StockView.alerts);
    });
  }

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

    // Semua toko (admin): peringatan stok seluruh toko; daftar & ubah stok
    // per toko setelah memilih toko.
    if (storeId == null) {
      final all = ref.watch(stockAlertsProvider(null));
      return LargeTitlePage(
        title: 'Stok',
        subtitle: 'Peringatan stok semua toko',
        actions: [
          AppButton(
            label: 'Pilih Toko',
            icon: CupertinoIcons.building_2_fill,
            onPressed: () => pickStoreScope(context, ref, allowAll: false),
          ),
        ],
        slivers: [
          SliverToBoxAdapter(
            child: all.when(
              loading: () => const SizedBox(height: 240, child: LoadingState()),
              error: (e, _) => ErrorBanner(message: 'Gagal memuat: $e'),
              data: (list) => StockAlertList(alerts: list),
            ),
          ),
        ],
      );
    }

    final filter = ProductFilter(text: _text, storeId: storeId);
    final count = ref.watch(productCountProvider(filter)).value;
    final page = ref.watch(productPageProvider((filter, 0)));
    final alerts = ref.watch(stockAlertsProvider(storeId));
    final alertCount = alerts.value == null
        ? null
        : {for (final a in alerts.value!) a.row.productId}.length;

    return LargeTitlePage(
      title: 'Stok',
      subtitle: store?.name,
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                  (
                    _StockView.alerts,
                    alertCount == null || alertCount == 0
                        ? 'Peringatan'
                        : 'Peringatan ($alertCount)',
                  ),
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
        if (_view == _StockView.alerts)
          SliverToBoxAdapter(
            child: alerts.when(
              loading: () => const SizedBox(height: 240, child: LoadingState()),
              error: (e, _) => ErrorBanner(message: 'Gagal memuat: $e'),
              data: (list) => StockAlertList(
                alerts: _text.trim().isEmpty
                    ? list
                    : [
                        for (final a in list)
                          if ('${a.row.name} ${a.row.code}'
                              .toLowerCase()
                              .contains(_text.trim().toLowerCase()))
                            a,
                      ],
                storeId: storeId,
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: page.when(
              loading: () => const SizedBox(height: 240, child: LoadingState()),
              error: (e, _) => ErrorBanner(message: 'Gagal memuat stok: $e'),
              data: (list) => list.isEmpty
                  ? Container(
                      constraints: const BoxConstraints(minHeight: 320),
                      alignment: Alignment.center,
                      child: const EmptyState(
                        icon: CupertinoIcons.archivebox,
                        title: 'Barang tidak ditemukan',
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
