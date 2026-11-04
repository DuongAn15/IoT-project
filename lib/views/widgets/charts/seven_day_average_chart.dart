import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/weather_unit_helper.dart';
import '../../../data/models/weather_daily_summary.dart';
import 'interactive_touch_tooltip.dart';

/// Biểu đồ so sánh xu hướng 7 ngày gần nhất (Bar / Column Chart)
class SevenDayAverageChart extends StatelessWidget {
  final List<WeatherDailySummary> dailySummaries;
  final WeatherMetricType metricType;

  const SevenDayAverageChart({
    super.key,
    required this.dailySummaries,
    required this.metricType,
  });

  Color _getMetricColor() {
    switch (metricType) {
      case WeatherMetricType.temperature:
        return AppColors.temperature;
      case WeatherMetricType.humidity:
        return AppColors.humidity;
      case WeatherMetricType.rainfall:
        return AppColors.rainfall;
      case WeatherMetricType.windSpeed:
        return AppColors.windSpeed;
    }
  }

  double _getValue(WeatherDailySummary summary) {
    switch (metricType) {
      case WeatherMetricType.temperature:
        return summary.avgTemperature;
      case WeatherMetricType.humidity:
        return summary.avgHumidity;
      case WeatherMetricType.rainfall:
        return summary.totalRainfall;
      case WeatherMetricType.windSpeed:
        return summary.avgWindSpeed;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (dailySummaries.isEmpty) {
      return const SizedBox(
        height: AppDimensions.chartHeightDefault,
        child: Center(child: Text('Chưa có dữ liệu 7 ngày')),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final metricColor = _getMetricColor();
    final dayLabels = dailySummaries.map((s) => s.dayOfWeek).toList();

    double dataMax = 0.0;

    for (final s in dailySummaries) {
      final val = _getValue(s);
      if (val > dataMax) dataMax = val;
    }

    final yConfig = WeatherUnitHelper.calculateYAxisConfig(
      metricType: metricType,
      dataMax: dataMax,
    );

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < dailySummaries.length; i++) {
      final summary = dailySummaries[i];
      final isToday = i == dailySummaries.length - 1;
      final val = _getValue(summary);

      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: val,
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: isToday
                    ? [metricColor, metricColor.withValues(alpha: 0.8)]
                    : [metricColor.withValues(alpha: 0.4), metricColor.withValues(alpha: 0.65)],
              ),
              width: 20,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppDimensions.radiusSm),
                topRight: Radius.circular(AppDimensions.radiusSm),
              ),
              borderSide: isToday
                  ? BorderSide(
                      color: isDark ? Colors.white : metricColor,
                      width: 1.5,
                    )
                  : BorderSide.none,
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
              metricType: metricType,
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
                  reservedSize: 34,
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
