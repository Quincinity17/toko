import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_dialogs.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../products/data/product_repository.dart';
import '../../../products/domain/product.dart';

/// Cari barang berdasarkan nama/kode/barcode (F3). Enter memilih hasil yang
/// disorot; panah atas/bawah memindah sorotan.
Future<Product?> showProductSearchSheet(
  BuildContext context, {
  String initialQuery = '',
}) {
  return AppDialogs.sheet<Product>(
    context,
    title: 'Cari Barang',
    maxWidth: 720,
    builder: (_) => _ProductSearch(initialQuery: initialQuery),
  );
}

class _ProductSearch extends ConsumerStatefulWidget {
  const _ProductSearch({required this.initialQuery});

  final String initialQuery;

  @override
  ConsumerState<_ProductSearch> createState() => _ProductSearchState();
}

class _ProductSearchState extends ConsumerState<_ProductSearch> {
  late final _query = TextEditingController(text: widget.initialQuery);
  Timer? _debounce;
  List<Product>? _results;

  /// `true` jika [_results] berisi saran nama yang mendekati, bukan hasil
  /// pencarian yang cocok.
  bool _suggested = false;
  int _highlight = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _search);
  }

  Future<void> _search() async {
    final text = _query.text;
    final repo = ref.read(productRepositoryProvider);
    var results = await repo.search(text);
    var suggested = false;
    if (results.isEmpty && text.trim().isNotEmpty) {
      results = await repo.suggest(text);
      suggested = results.isNotEmpty;
    }
    if (!mounted || text != _query.text) return;
    setState(() {
      _results = results;
      _suggested = suggested;
      _highlight = 0;
    });
  }

  void _pick(Product p) => Navigator.pop(context, p);

  void _move(int delta) {
    final n = _results?.length ?? 0;
    if (n == 0) return;
    setState(() => _highlight = (_highlight + delta).clamp(0, n - 1));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final results = _results;
    final height = MediaQuery.sizeOf(context).height * 0.7;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
      },
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.sm,
              ),
              child: CupertinoSearchTextField(
                controller: _query,
                autofocus: true,
                placeholder: 'Nama, kode, atau barcode',
                style: AppTypography.body.copyWith(color: c.label),
                onChanged: _onChanged,
                onSubmitted: (_) {
                  if (results != null && results.isNotEmpty) {
                    _pick(results[_highlight]);
                  }
                },
              ),
            ),
            Expanded(
              child: results == null
                  ? const LoadingState()
                  : results.isEmpty
                  ? EmptyState(
                      icon: CupertinoIcons.search,
                      title: 'Barang tidak ditemukan',
                      message: _query.text.isEmpty
                          ? null
                          : 'Tidak ada barang yang cocok atau mirip dengan '
                                '"${_query.text}". Periksa ejaan, atau cari '
                                'dengan kode/barcode.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_suggested) _SuggestionHeader(query: _query.text),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.md,
                              0,
                              AppSpacing.md,
                              AppSpacing.md,
                            ),
                            itemCount: results.length,
                            itemBuilder: (context, i) => _ResultTile(
                              product: results[i],
                              highlighted: i == _highlight,
                              onTap: () => _pick(results[i]),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keterangan di atas daftar saran saat tidak ada yang cocok persis.
class _SuggestionHeader extends StatelessWidget {
  const _SuggestionHeader({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.lightbulb_fill, size: 16, color: c.warning),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Tidak ada yang cocok dengan "$query". '),
                  TextSpan(
                    text: 'Mungkin maksud Anda:',
                    style: TextStyle(
                      color: c.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              style: AppTypography.subheadline.copyWith(
                color: c.labelSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({
    required this.product,
    required this.highlighted,
    required this.onTap,
  });

  final Product product;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = product;
    return PressableScale(
      onPressed: onTap,
      pressedScale: 0.99,
      borderRadius: AppRadius.mdAll,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: highlighted ? c.accentTint : Colors.transparent,
          borderRadius: AppRadius.mdAll,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: AppTypography.body.copyWith(
                      color: c.label,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    [
                      p.code,
                      if (p.barcode != null) p.barcode!,
                      if (p.categoryName != null) p.categoryName!,
                    ].join(' · '),
                    style: AppTypography.footnote.copyWith(
                      color: c.labelSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Fmt.rupiah(p.sellingPrice),
                  style: AppTypography.body.copyWith(
                    color: c.label,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Stok ${Fmt.number(p.stock)} ${p.unitName ?? ''}',
                  style: AppTypography.footnote.copyWith(
                    color: p.isLowStock ? c.warning : c.labelSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
