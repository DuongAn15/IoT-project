import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/weather_unit_helper.dart';
import '../../../data/models/weather_daily_summary.dart';
import 'interactive_touch_tooltip.dart';

/// Biểu đồ cột lượng mưa 7 ngày gần nhất (mm)
class RainfallBarChart extends StatelessWidget {
  final List<WeatherDailySummary> dailySummaries;

  const RainfallBarChart({
    super.key,
    required this.dailySummaries,
  });

  @override
  Widget build(BuildContext context) {
    if (dailySummaries.isEmpty) {
      return const SizedBox(
        height: AppDimensions.chartHeightDefault,
        child: Center(child: Text('Chưa có dữ liệu lượng mưa')),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dayLabels = dailySummaries.map((s) => s.dayOfWeek).toList();

    double dataMax = 0.0;
    for (final s in dailySummaries) {
      if (s.totalRainfall > dataMax) dataMax = s.totalRainfall;
    }

    final yConfig = WeatherUnitHelper.calculateYAxisConfig(
      metricType: WeatherMetricType.rainfall,
      dataMax: dataMax,
    );

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < dailySummaries.length; i++) {
      final summary = dailySummaries[i];
      final isToday = i == dailySummaries.length - 1;

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: summary.totalRainfall,
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: isToday
                    ? [const Color(0xFF0891B2), const Color(0xFF22D3EE)]
                    : [const Color(0xFF0284C7).withValues(alpha: 0.6), const Color(0xFF38BDF8).withValues(alpha: 0.8)],
              ),
              width: 18,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppDimensions.radiusXs),
                topRight: Radius.circular(AppDimensions.radiusXs),
              ),
            ),
          ],
        ),
      );
    }

    return RepaintBoundary(
      child: SizedBox(
        height: AppDimensions.chartHeightDefault,
        child: BarChart(
          BarChartData(
            barTouchData: InteractiveTouchTooltipHelper.create7dBarTouchData(
              context: context,
              metricType: WeatherMetricType.rainfall,
              dayLabels: dayLabels,
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: yConfig.interval,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  strokeWidth: 1,
                  dashArray: [5, 5],
                );
              },
            ),
            titlesData: FlTitlesData(
              show: true,
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: yConfig.interval,
                  getTitlesWidget: (value, meta) {
                    final remainder = (value - yConfig.minY) % yConfig.interval;
                    final isMultiple = remainder.abs() < 0.01 || (yConfig.interval - remainder).abs() < 0.01;
                    if (!isMultiple) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      space: 4,
                      child: Text(
                        value.round().toString(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                        ),
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= dayLabels.length) return const SizedBox.shrink();
                    final isToday = index == dayLabels.length - 1;

                    return Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        dayLabels[index],
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isToday
                              ? (isDark ? AppColors.primaryDark : AppColors.primaryLight)
                              : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight),
                          fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minY: yConfig.minY,
            maxY: yConfig.maxY,
            barGroups: barGroups,
          ),
        ),
      ),
    );
  }
}
