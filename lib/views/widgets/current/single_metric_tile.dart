import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/weather_unit_helper.dart';

/// Thẻ hiển thị một trong 4 chỉ số cảm biến cốt lõi
class SingleMetricTile extends StatelessWidget {
  final WeatherMetricType type;
  final double value;
  final String assessment;
  final VoidCallback? onTap;

  const SingleMetricTile({
    super.key,
    required this.type,
    required this.value,
    required this.assessment,
    this.onTap,
  });

  Color _getAccentColor(bool isDark) {
    switch (type) {
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

  Color _getBgColor(bool isDark) {
    switch (type) {
      case WeatherMetricType.temperature:
        return isDark ? AppColors.temperatureBgDark : AppColors.temperatureBg;
      case WeatherMetricType.humidity:
        return isDark ? AppColors.humidityBgDark : AppColors.humidityBg;
      case WeatherMetricType.rainfall:
        return isDark ? AppColors.rainfallBgDark : AppColors.rainfallBg;
      case WeatherMetricType.windSpeed:
        return isDark ? AppColors.windSpeedBgDark : AppColors.windSpeedBg;
    }
  }

  String _formatValue() {
    switch (type) {
      case WeatherMetricType.temperature:
        return value.toStringAsFixed(1);
      case WeatherMetricType.humidity:
        return value.toStringAsFixed(0);
      case WeatherMetricType.rainfall:
        return value.toStringAsFixed(1);
      case WeatherMetricType.windSpeed:
        return value.toStringAsFixed(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = _getAccentColor(isDark);
    final iconBgColor = _getBgColor(isDark);

    return Material(
      color: theme.cardTheme.color,
      shape: theme.cardTheme.shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.spaceMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Row: Icon with circular background + Metric Name
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppDimensions.spaceSm),
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      type.icon,
                      size: AppDimensions.iconMd,
                      color: accentColor,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: AppDimensions.iconSm,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                ],
              ),
              const SizedBox(height: AppDimensions.spaceSm),

              // Middle: Metric Value + Unit
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _formatValue(),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.spaceXs),
                  Text(
                    type.unit,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                ],
              ),

              // Bottom: Qualitative Assessment Text
              Text(
                '$assessment • ${type.labelVi}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
