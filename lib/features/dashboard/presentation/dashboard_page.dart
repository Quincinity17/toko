import 'package:flutter/cupertino.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/state_views.dart';
import 'widgets/stat_card.dart';

/// Kerangka dashboard. Angka masih nol; diisi dari data penjualan di Langkah 7.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return LargeTitlePage(
      title: 'Dashboard',
      subtitle: Fmt.dateLong(DateTime.now()),
      slivers: [
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1000
                  ? 4
                  : constraints.maxWidth > 560
                  ? 2
                  : 1;
              const gap = AppSpacing.md;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              final cards = [
                StatCard(
                  label: 'Omzet Hari Ini',
                  value: Fmt.rupiah(0),
                  icon: CupertinoIcons.money_dollar_circle_fill,
                  color: c.success,
                ),
                StatCard(
                  label: 'Transaksi',
                  value: '0',
                  icon: CupertinoIcons.doc_text_fill,
                  color: c.accent,
                ),
                StatCard(
                  label: 'Produk Terlaris',
                  value: '–',
                  icon: CupertinoIcons.star_fill,
                  color: c.warning,
                ),
                StatCard(
                  label: 'Stok Menipis',
                  value: '0',
                  icon: CupertinoIcons.exclamationmark_triangle_fill,
                  color: c.danger,
                ),
              ];
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final card in cards) SizedBox(width: width, child: card),
                ],
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        SliverToBoxAdapter(
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Penjualan 7 Hari Terakhir',
                  style: AppTypography.headline.copyWith(color: c.label),
                ),
                const SizedBox(
                  height: 280,
                  child: EmptyState(
                    icon: CupertinoIcons.chart_bar_alt_fill,
                    title: 'Belum ada penjualan',
                    message: 'Grafik akan muncul setelah ada transaksi.',
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
