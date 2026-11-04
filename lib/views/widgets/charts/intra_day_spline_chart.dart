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

    // Tính toán FlSpots
    final spots = <FlSpot>[];
    double minY = double.infinity;
    double maxY = -double.infinity;

    for (final p in points) {
      final val = _getValue(p);
      spots.add(FlSpot(p.minutesFromMidnight.toDouble(), val));
      if (val < minY) minY = val;
      if (val > maxY) maxY = val;
    }

    // Đệm khoảng cách cho trục Y
    final ySpan = (maxY - minY).abs();
    final yPadding = ySpan == 0 ? 2.0 : ySpan * 0.15;
    final chartMinY = max(0.0, (minY - yPadding).floorToDouble());
    final chartMaxY = (maxY + yPadding).ceilToDouble();

    // Giới hạn trục X: từ 00:00 (0) đến hiện tại (hoặc cuối ngày 1440)
    final maxX = max(180.0, points.last.minutesFromMidnight.toDouble());

    return RepaintBoundary(
      child: SizedBox(
        height: isCompact ? AppDimensions.chartHeightCompact : AppDimensions.chartHeightDefault,
        child: LineChart(
          LineChartData(
            lineTouchData: InteractiveTouchTooltipHelper.create5mLineTouchData(
              context: context,
              metricType: metricType,
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: max(1.0, (chartMaxY - chartMinY) / 4),
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
                  showTitles: !isCompact,
                  reservedSize: 36,
                  interval: max(1.0, (chartMaxY - chartMinY) / 4),
                  getTitlesWidget: (value, meta) {
                    return Text(
                      value.toStringAsFixed(0),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  // Đánh dấu mỗi 3 giờ (180 phút): 00:00, 03:00, 06:00, 09:00, 12:00, 15:00, 18:00, 21:00
                  interval: 180,
                  getTitlesWidget: (value, meta) {
                    final int val = value.toInt();
                    // Chỉ hiển thị nhãn chia hết cho 180 và <= maxX
                    if (val % 180 != 0 || val > maxX) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        DateTimeFormatter.minutesToTime(val),
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
            minY: chartMinY,
            maxY: chartMaxY,
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                curveSmoothness: 0.25,
                preventCurveOverShooting: true,
                color: metricColor,
                barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: fillGradient,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
