import 'package:flutter/cupertino.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/large_title_page.dart';
import '../../../core/widgets/state_views.dart';

enum ReportRange { today, week, month, custom }

/// Placeholder laporan; dibangun di Langkah 7.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportRange _range = ReportRange.today;

  @override
  Widget build(BuildContext context) {
    return LargeTitlePage(
      title: 'Laporan',
      bottom: Align(
        alignment: Alignment.centerLeft,
        child: CupertinoSlidingSegmentedControl<ReportRange>(
          groupValue: _range,
          padding: const EdgeInsets.all(3),
          onValueChanged: (v) => setState(() => _range = v ?? _range),
          children: const {
            ReportRange.today: _Segment('Hari Ini'),
            ReportRange.week: _Segment('7 Hari'),
            ReportRange.month: _Segment('30 Hari'),
            ReportRange.custom: _Segment('Pilih Tanggal'),
          },
        ),
      ),
      child: const EmptyState(
        icon: CupertinoIcons.chart_bar,
        title: 'Belum ada data',
        message: 'Laporan penjualan per tanggal muncul setelah ada transaksi.',
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Text(label, style: AppTypography.subheadline),
    );
  }
}
