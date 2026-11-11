import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/weather_unit_helper.dart';
import '../../../data/models/weather_point_5m.dart';
import 'interactive_touch_tooltip.dart';

/// Biểu đồ đường cong mượt mà (Spline Line Chart) cho chuỗi mốc 5 phút trong ngày
/// Bọc RepaintBoundary đảm bảo 60fps khi chạm lướt tay.
class IntraDaySplineChart extends StatelessWidget {
  final List<WeatherPoint5m> points;
  final WeatherMetricType metricType;
  final bool isCompact;

  const IntraDaySplineChart({
    super.key,
    required this.points,
    required this.metricType,
    this.isCompact = false,
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

  LinearGradient _getFillGradient() {
    switch (metricType) {
      case WeatherMetricType.temperature:
        return AppColors.tempChartGradient;
      case WeatherMetricType.humidity:
        return AppColors.humidityChartGradient;
      case WeatherMetricType.rainfall:
        return AppColors.rainChartGradient;
      case WeatherMetricType.windSpeed:
        return AppColors.windChartGradient;
    }
  }

  double _getValue(WeatherPoint5m point) {
    switch (metricType) {
      case WeatherMetricType.temperature:
        return point.temperature;
      case WeatherMetricType.humidity:
        return point.humidity;
      case WeatherMetricType.rainfall:
        return point.rainfall;
      case WeatherMetricType.windSpeed:
        return point.windSpeed;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(
        height: AppDimensions.chartHeightDefault,
        child: Center(child: Text('Chưa có dữ liệu đo trong ngày')),
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final metricColor = _getMetricColor();
    final fillGradient = _getFillGradient();

    // Tính toán FlSpots & dataMax (đảm bảo không trùng mốc X và sắp xếp tăng dần)
    final Map<double, double> spotMap = {};
    double dataMax = 0.0;

    for (final p in points) {
      final x = p.minutesFromMidnight.toDouble().clamp(0.0, 1440.0);
      final val = _getValue(p);
      spotMap[x] = val;
      if (val > dataMax) dataMax = val;
    }

    final sortedKeys = spotMap.keys.toList()..sort();
    final spots = sortedKeys.map((x) => FlSpot(x, spotMap[x]!)).toList();

    final yConfig = WeatherUnitHelper.calculateYAxisConfig(
      metricType: metricType,
      dataMax: dataMax,
      isCompact: isCompact,
    );

    // Giới hạn trục X: làm tròn lên mốc 3 giờ (180 phút) kế tiếp bao trọn cả dữ liệu và thời điểm hiện tại
    final nowGmt7 = DateTimeFormatter.currentGmt7Time();
    final currentMinutes = (nowGmt7.hour * 60 + nowGmt7.minute).toDouble();
    final maxDataX = sortedKeys.isNotEmpty ? sortedKeys.last : 180.0;
    final targetMax = max(maxDataX, currentMinutes);
    final double maxX = ((targetMax / 180).ceil() * 180.0).clamp(180.0, 1440.0);

    return RepaintBoundary(
      child: SizedBox(
        height: isCompact ? AppDimensions.chartHeightCompact : AppDimensions.chartHeightDefault,
        child: LineChart(
          LineChartData(
            clipData: const FlClipData.all(),
            lineTouchData: InteractiveTouchTooltipHelper.create5mLineTouchData(
              context: context,
              metricType: metricType,
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
                  // Đánh dấu mỗi 3 giờ (180 phút): 0h, 3h, 6h, 9h, 12h, 15h, 18h, 21h
                  interval: 180,
                  getTitlesWidget: (value, meta) {
                    final int val = value.toInt();
                    // Chỉ hiển thị nhãn chia hết cho 180 và <= maxX
                    if (val % 180 != 0 || val > maxX) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      space: 6,
                      fitInside: SideTitleFitInsideData.fromTitleMeta(meta, distanceFromEdge: 6),
                      child: Text(
                        DateTimeFormatter.minutesToHourLabel(val),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: maxX,
            minY: yConfig.minY,
            maxY: yConfig.maxY,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: spots.length > 1,
                curveSmoothness: 0.2,
                preventCurveOverShooting: true,
                color: metricColor,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: spots.length <= 1,
                  getDotPainter: (spot, percent, barData, index) {
                    return FlDotCirclePainter(
                      radius: 4,
                      color: metricColor,
                      strokeWidth: 2,
                      strokeColor: Colors.white,
                    );
                  },
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: fillGradient,
                ),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
        ),
      ),
    );
  }
}
