import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Satu seri data grafik. Warna mengikuti entitas (bukan urutan), jadi seri
/// yang sama selalu berwarna sama walau seri lain disembunyikan.
class ChartSeries {
  const ChartSeries({
    required this.label,
    required this.color,
    required this.values,
  });

  final String label;
  final Color color;
  final List<num> values;
}

/// Langkah sumbu Y yang "bulat" (1, 2, 2,5, 5 × 10ⁿ) supaya label rapi.
double _niceStep(double max, int ticks) {
  if (max <= 0) return 1;
  final raw = max / ticks;
  final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in [1, 2, 2.5, 5, 10]) {
    if (raw <= m * exp) return m * exp;
  }
  return 10 * exp;
}

FlGridData _grid(AppColors c, double step) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: step,
  getDrawingHorizontalLine: (_) =>
      FlLine(color: c.separator.withValues(alpha: 0.5), strokeWidth: 1),
);

AxisTitles _yAxis(AppColors c, double step) => AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: 52,
    interval: step,
    getTitlesWidget: (value, meta) => SideTitleWidget(
      meta: meta,
      child: Text(
        Fmt.compact(value),
        style: AppTypography.caption.copyWith(
          color: c.labelSecondary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ),
  ),
);

const _noTitles = AxisTitles();

/// Legenda dengan kunci garis/kotak dan teks berwarna teks (bukan warna seri).
class ChartLegend extends StatelessWidget {
  const ChartLegend({super.key, required this.series, this.box = false});

  final List<ChartSeries> series;

  /// `true` untuk batang (kunci kotak), `false` untuk garis.
  final bool box;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xxs,
      children: [
        for (final s in series)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: box ? 10 : 14,
                height: box ? 10 : 2,
                decoration: BoxDecoration(
                  color: s.color,
                  borderRadius: BorderRadius.circular(box ? 2 : 1),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                s.label,
                style: AppTypography.footnote.copyWith(color: c.labelSecondary),
              ),
            ],
          ),
      ],
    );
  }
}

/// Grafik garis tren (satu sumbu Y, Rupiah). Satu seri → area tipis di bawah
/// garis; dua seri atau lebih → legenda di atas. Hover/ketuk menampilkan
/// garis bantu vertikal dan nilai semua seri pada titik itu.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.series,
    required this.xLabels,
    this.height = 240,
    this.valueFormatter = Fmt.rupiah,
  });

  final List<ChartSeries> series;

  /// Label sumbu X per titik (mis. "Kam 15").
  final List<String> xLabels;
  final double height;
  final String Function(num) valueFormatter;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final count = xLabels.length;
    final maxY = series
        .expand((s) => s.values)
        .fold<num>(0, (m, v) => v > m ? v : m)
        .toDouble();
    final step = _niceStep(maxY, 4);
    final top = maxY <= 0 ? step * 4 : (maxY / step).ceil() * step;
    // Label X dijarangkan supaya tidak bertabrakan.
    final labelEvery = (count / 7).ceil().clamp(1, count);
    final single = series.length == 1;

    final chart = LineChart(
      LineChartData(
        minX: 0,
        maxX: (count - 1).toDouble().clamp(1, double.infinity),
        minY: 0,
        maxY: top,
        gridData: _grid(c, step),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: _yAxis(c, step),
          rightTitles: _noTitles,
          topTitles: _noTitles,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.round();
                if (i < 0 || i >= count || value != i.toDouble()) {
                  return const SizedBox.shrink();
                }
                final show =
                    i == count - 1 || (count - 1 - i) % labelEvery == 0;
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    show ? xLabels[i] : '',
                    style: AppTypography.caption.copyWith(
                      color: c.labelSecondary,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          getTouchedSpotIndicator: (bar, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                FlLine(color: c.labelTertiary, strokeWidth: 1),
                FlDotData(
                  getDotPainter: (spot, p, b, i) => FlDotCirclePainter(
                    radius: 4,
                    color: b.color ?? c.accent,
                    strokeWidth: 2,
                    strokeColor: c.card,
                  ),
                ),
              ),
          ],
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => c.cardElevated,
            tooltipBorder: BorderSide(color: c.separator, width: 0.5),
            tooltipBorderRadius: AppRadius.smAll,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final (i, s) in spots.indexed)
                LineTooltipItem(
                  // Nilai dulu (tebal), lalu nama seri; tanggal di baris pertama.
                  i == 0 ? '${xLabels[s.x.round()]}\n' : '',
                  AppTypography.caption.copyWith(color: c.labelSecondary),
                  textAlign: TextAlign.left,
                  children: [
                    TextSpan(
                      text: valueFormatter(s.y),
                      style: AppTypography.footnote.copyWith(
                        color: c.label,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: '  ${series[s.barIndex].label}',
                      style: AppTypography.caption.copyWith(
                        color: c.labelSecondary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (final s in series)
            LineChartBarData(
              spots: [
                for (var i = 0; i < s.values.length; i++)
                  FlSpot(i.toDouble(), s.values[i].toDouble()),
              ],
              isCurved: true,
              preventCurveOverShooting: true,
              curveSmoothness: 0.25,
              barWidth: 2,
              isStrokeCapRound: true,
              isStrokeJoinRound: true,
              color: s.color,
              // Titik akhir saja, dengan cincin warna permukaan.
              dotData: FlDotData(
                checkToShowDot: (spot, bar) => spot.x == bar.spots.last.x,
                getDotPainter: (spot, p, b, i) => FlDotCirclePainter(
                  radius: 4,
                  color: s.color,
                  strokeWidth: 2,
                  strokeColor: c.card,
                ),
              ),
              belowBarData: BarAreaData(
                show: single,
                color: s.color.withValues(alpha: 0.10),
              ),
            ),
        ],
      ),
      duration: AppDurations.medium,
      curve: SpringCurve.smooth,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!single) ...[
          ChartLegend(series: series),
          const SizedBox(height: AppSpacing.sm),
        ],
        SizedBox(height: height, child: chart),
      ],
    );
  }
}

/// Grafik batang satu seri (mis. penjualan per jam). Batang ≤ 24 px dengan
/// ujung atas membulat 4 px; hover menampilkan label dan nilai batang itu.
class ColumnChart extends StatelessWidget {
  const ColumnChart({
    super.key,
    required this.values,
    required this.xLabels,
    required this.color,
    required this.seriesLabel,
    this.height = 220,
    this.valueFormatter = Fmt.rupiah,
    this.labelEvery = 1,
  });

  final List<num> values;
  final List<String> xLabels;
  final Color color;
  final String seriesLabel;
  final double height;
  final String Function(num) valueFormatter;

  /// Tampilkan label sumbu X setiap n batang (mis. 3 untuk 24 jam).
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxY = values.fold<num>(0, (m, v) => v > m ? v : m).toDouble();
    final step = _niceStep(maxY, 4);
    final top = maxY <= 0 ? step * 4 : (maxY / step).ceil() * step;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slot = (constraints.maxWidth - 60) / values.length;
          final width = math.min(24.0, slot * 0.6);
          return BarChart(
            BarChartData(
              maxY: top,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              gridData: _grid(c, step),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: _yAxis(c, step),
                rightTitles: _noTitles,
                topTitles: _noTitles,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(
                          i % labelEvery == 0 ? xLabels[i] : '',
                          style: AppTypography.caption.copyWith(
                            color: c.labelSecondary,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => c.cardElevated,
                  tooltipBorder: BorderSide(color: c.separator, width: 0.5),
                  tooltipBorderRadius: AppRadius.smAll,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                    '${xLabels[group.x]}\n',
                    AppTypography.caption.copyWith(color: c.labelSecondary),
                    children: [
                      TextSpan(
                        text: valueFormatter(rod.toY),
                        style: AppTypography.footnote.copyWith(
                          color: c.label,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: '  $seriesLabel',
                        style: AppTypography.caption.copyWith(
                          color: c.labelSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < values.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: values[i].toDouble(),
                        width: width,
                        color: color,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            duration: AppDurations.medium,
            curve: SpringCurve.smooth,
          );
        },
      ),
    );
  }
}
