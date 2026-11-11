import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/date_time_formatter.dart';
import '../../../core/utils/weather_unit_helper.dart';

import '../../../data/models/weather_daily_summary.dart';

/// Helper tạo Tooltip khi người dùng chạm và lướt tay trên biểu đồ fl_chart
abstract class InteractiveTouchTooltipHelper {
  /// Cấu hình LineTouchData cho biểu đồ mốc 5 phút trong ngày
  static LineTouchData create5mLineTouchData({
    required BuildContext context,
    required WeatherMetricType metricType,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LineTouchData(
      enabled: true,
      handleBuiltInTouches: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => isDark ? AppColors.surfaceVariantDark : Colors.white,
        tooltipRoundedRadius: AppDimensions.radiusSm,
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tooltipBorder: BorderSide(
          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
          width: 1.0,
        ),
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((spot) {
            final minutes = spot.x.toInt();
            final timeStr = DateTimeFormatter.minutesToTime(minutes);
            final valueStr = spot.y.toStringAsFixed(metricType == WeatherMetricType.humidity ? 0 : 1);

            return LineTooltipItem(
              '$timeStr\n',
              theme.textTheme.labelSmall!.copyWith(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                fontWeight: FontWeight.w500,
              ),
              children: [
                TextSpan(
                  text: '$valueStr ${metricType.unit}',
                  style: theme.textTheme.labelLarge!.copyWith(
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
          }).toList();
        },
      ),
      getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
        return spotIndexes.map((spotIndex) {
          return TouchedSpotIndicatorData(
            FlLine(
              color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
              strokeWidth: 1.5,
              dashArray: [4, 4],
            ),
            FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 5,
                  color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              },
            ),
          );
        }).toList();
      },
    );
  }

  /// Cấu hình BarTouchData cho biểu đồ 7 ngày
  static BarTouchData create7dBarTouchData({
    required BuildContext context,
    required WeatherMetricType metricType,
    required List<String> dayLabels,
    List<WeatherDailySummary>? summaries,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return BarTouchData(
      enabled: true,
      touchTooltipData: BarTouchTooltipData(
        getTooltipColor: (_) => isDark ? AppColors.surfaceVariantDark : Colors.white,
        tooltipRoundedRadius: AppDimensions.radiusSm,
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        tooltipBorder: BorderSide(
          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
          width: 1.0,
        ),
        getTooltipItem: (group, groupIndex, rod, rodIndex) {
          final dayLabel = (groupIndex >= 0 && groupIndex < dayLabels.length)
              ? dayLabels[groupIndex]
              : '';

          final hasData = (summaries != null && groupIndex >= 0 && groupIndex < summaries.length)
              ? summaries[groupIndex].hasData
              : true;

          if (!hasData) {
            return BarTooltipItem(
              '$dayLabel\n',
              theme.textTheme.labelSmall!.copyWith(
                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                fontWeight: FontWeight.w500,
              ),
              children: [
                TextSpan(
                  text: 'None',
                  style: theme.textTheme.labelLarge!.copyWith(
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
          }

          final valueStr = rod.toY.toStringAsFixed(metricType == WeatherMetricType.humidity ? 0 : 1);

          return BarTooltipItem(
            '$dayLabel\n',
            theme.textTheme.labelSmall!.copyWith(
              color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
              fontWeight: FontWeight.w500,
            ),
            children: [
              TextSpan(
                text: '$valueStr ${metricType.unit}',
                style: theme.textTheme.labelLarge!.copyWith(
                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
