import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/state_views.dart';
import '../../../data/models/platform.dart';

const _gridColor = AppColors.border;
const _axisTextStyle = TextStyle(fontSize: 10.5, color: AppColors.textMuted);

/// Sales trend: single series -> sequential blue, thin line, gradient fill,
/// crosshair tooltip on hover. No legend needed for one series (title names it).
class SalesTrendChart extends StatelessWidget {
  const SalesTrendChart({super.key, required this.points, this.loading = false});
  final List<TrendPoint> points;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Padding(padding: EdgeInsets.all(Gap.lg), child: Skeleton(height: 180));
    if (points.every((p) => p.value == 0)) {
      return const SizedBox(height: 200, child: EmptyView(compact: true, icon: Icons.show_chart, title: 'No sales in this period'));
    }
    final maxY = points.map((p) => p.value).fold<double>(0, (a, b) => a > b ? a : b) * 1.2;
    final step = (points.length / 6).ceil().clamp(1, points.length);
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 10 : maxY,
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxY / 4 <= 0 ? 1 : maxY / 4, getDrawingHorizontalLine: (_) => const FlLine(color: _gridColor, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, meta) => Text(Fmt.moneyCompact(v), style: _axisTextStyle))),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                interval: step.toDouble(),
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox();
                  return Padding(padding: const EdgeInsets.only(top: 6), child: Text(Fmt.shortDate(points[i].date), style: _axisTextStyle));
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.textPrimary,
              getTooltipItems: (spots) => spots.map((s) {
                final p = points[s.x.toInt()];
                return LineTooltipItem('${Fmt.date(p.date)}\n', const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600), children: [
                  TextSpan(text: Fmt.money(p.value), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ]);
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value)],
              isCurved: true,
              curveSmoothness: 0.2,
              color: AppColors.chartSeries[0],
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.chartSeries[0].withValues(alpha: 0.18), AppColors.chartSeries[0].withValues(alpha: 0.0)]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Store-wise sales: categorical bars, one color per entity (fixed order),
/// rounded top, per-bar hover tooltip.
class StoreSalesChart extends StatelessWidget {
  const StoreSalesChart({super.key, required this.data, this.loading = false});
  final List<NamedValue> data;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Padding(padding: EdgeInsets.all(Gap.lg), child: Skeleton(height: 180));
    if (data.isEmpty) return const SizedBox(height: 200, child: EmptyView(compact: true, icon: Icons.storefront_outlined, title: 'No store sales yet'));
    final maxY = data.map((d) => d.value).fold<double>(0, (a, b) => a > b ? a : b) * 1.25;
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 10 : maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: _gridColor, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44, getTitlesWidget: (v, meta) => Text(Fmt.moneyCompact(v), style: _axisTextStyle))),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= data.length) return const SizedBox();
                  return Padding(padding: const EdgeInsets.only(top: 6), child: Text(data[i].name, style: _axisTextStyle, maxLines: 1, overflow: TextOverflow.ellipsis));
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.textPrimary,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                '${data[groupIndex].name}\n',
                const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                children: [TextSpan(text: Fmt.money(rod.toY), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))],
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(toY: data[i].value, color: AppColors.chartSeries[0], width: 22, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Top products: horizontal bars ranked by quantity sold.
class TopProductsChart extends StatelessWidget {
  const TopProductsChart({super.key, required this.data, this.loading = false});
  final List<NamedValue> data;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Padding(padding: EdgeInsets.all(Gap.lg), child: Skeleton(height: 220));
    if (data.isEmpty) return const SizedBox(height: 220, child: EmptyView(compact: true, icon: Icons.inventory_2_outlined, title: 'No sales data yet'));
    final maxV = data.map((d) => d.value).fold<double>(0, (a, b) => a > b ? a : b);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in data.take(8))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(children: [
              SizedBox(
                width: 130,
                child: Text(item.name, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Expanded(
                child: Stack(children: [
                  Container(height: 16, decoration: BoxDecoration(color: AppColors.neutralSoft, borderRadius: BorderRadius.circular(4))),
                  FractionallySizedBox(
                    widthFactor: maxV <= 0 ? 0 : (item.value / maxV).clamp(0.02, 1.0),
                    child: Container(height: 16, decoration: BoxDecoration(color: AppColors.chartSeries[0], borderRadius: BorderRadius.circular(4))),
                  ),
                ]),
              ),
              const SizedBox(width: Gap.sm),
              SizedBox(width: 44, child: Text(Fmt.number(item.value), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            ]),
          ),
      ],
    );
  }
}

/// Stock movement: two series in the SAME unit (units), single axis, legend
/// shown (>=2 series), fixed categorical colors (slot 1 = in, slot 2 = out).
class StockMovementChart extends StatelessWidget {
  const StockMovementChart({super.key, required this.points, this.loading = false});
  final List<TrendPoint> points;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Padding(padding: EdgeInsets.all(Gap.lg), child: Skeleton(height: 180));
    if (points.every((p) => p.value == 0 && p.secondary == 0)) {
      return const SizedBox(height: 220, child: EmptyView(compact: true, icon: Icons.swap_vert, title: 'No stock movement in this period'));
    }
    final maxY = points.map((p) => p.value > p.secondary ? p.value : p.secondary).fold<double>(0, (a, b) => a > b ? a : b) * 1.25;
    final step = (points.length / 7).ceil().clamp(1, points.length);
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        _LegendDot(color: AppColors.chartSeries[0], label: 'Inbound'),
        const SizedBox(width: Gap.lg),
        _LegendDot(color: AppColors.chartSeries[7], label: 'Outbound'),
      ]),
      const SizedBox(height: Gap.sm),
      SizedBox(
        height: 200,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY <= 0 ? 10 : maxY,
            gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: _gridColor, strokeWidth: 1)),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (v, meta) => Text(Fmt.number(v), style: _axisTextStyle))),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  interval: step.toDouble(),
                  getTitlesWidget: (v, meta) {
                    final i = v.toInt();
                    if (i < 0 || i >= points.length) return const SizedBox();
                    return Padding(padding: const EdgeInsets.only(top: 6), child: Text(Fmt.shortDate(points[i].date), style: _axisTextStyle));
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => AppColors.textPrimary,
                getTooltipItems: (spots) => spots.map((s) {
                  final p = points[s.x.toInt()];
                  final isIn = s.barIndex == 0;
                  return LineTooltipItem(
                    '${Fmt.date(p.date)}\n',
                    const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    children: [TextSpan(text: '${isIn ? 'In' : 'Out'}: ${Fmt.number(isIn ? p.value : p.secondary)}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))],
                  );
                }).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value)],
                isCurved: true,
                curveSmoothness: 0.2,
                color: AppColors.chartSeries[0],
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
              LineChartBarData(
                spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].secondary)],
                isCurved: true,
                curveSmoothness: 0.2,
                color: AppColors.chartSeries[7],
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
    ]);
  }
}
