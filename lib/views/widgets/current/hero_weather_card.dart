import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/weather_unit_helper.dart';
import '../../../data/models/weather_current_model.dart';

/// Thẻ Anh Hùng Thời Tiết Hợp Nhất (Unified Hero Weather Card)
/// Tích hợp toàn diện trạng thái thời tiết, nhiệt độ tức thời và cả 4 chỉ số cảm biến vào cùng một khối thống nhất.
class HeroWeatherCard extends StatelessWidget {
  final WeatherCurrentModel current;
  final double? minTemp;
  final double? maxTemp;
  final Function(WeatherMetricType)? onMetricTap;

  const HeroWeatherCard({
    super.key,
    required this.current,
    this.minTemp,
    this.maxTemp,
    this.onMetricTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final overallStatus = WeatherUnitHelper.getOverallWeatherStatus(
      temp: current.temperature,
      rain: current.rainfall,
      wind: current.windSpeed,
    );
    final weatherIcon = WeatherUnitHelper.getOverallWeatherIcon(
      temp: current.temperature,
      rain: current.rainfall,
      wind: current.windSpeed,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.spaceLg),
      decoration: BoxDecoration(
        gradient: isDark ? AppColors.heroGradientDark : AppColors.heroGradientLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusXl),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : AppColors.primaryLight).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top row: Weather status badge + Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimensions.spaceSm + 4,
                  vertical: AppDimensions.spaceXs + 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      weatherIcon,
                      color: AppColors.accentSunDark,
                      size: AppDimensions.iconSm,
                    ),
                    const SizedBox(width: AppDimensions.spaceXs + 2),
                    Text(
                      overallStatus,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                weatherIcon,
                color: Colors.white.withValues(alpha: 0.9),
                size: AppDimensions.iconXl,
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.spaceMd),

          // 2. Main Temperature & Min/Max Info (Tapping navigates to Temperature chart)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onMetricTap?.call(WeatherMetricType.temperature),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      current.temperature.toStringAsFixed(1),
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 54,
                      ),
                    ),
                    Text(
                      '°C',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (minTemp != null && maxTemp != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Thấp: ${minTemp!.toStringAsFixed(1)}°',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Cao: ${maxTemp!.toStringAsFixed(1)}°',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.spaceMd),

          // 3. Embedded 3 Metrics Bar (Độ ẩm, Lượng mưa, Tốc độ gió) trong cùng khối
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                // Độ ẩm
                _buildMetricColumn(
                  context: context,
                  icon: Icons.water_drop_rounded,
                  label: 'Độ ẩm',
                  value: '${current.humidity.toStringAsFixed(0)}%',
                  subText: WeatherUnitHelper.getHumidityAssessment(current.humidity),
                  onTap: () => onMetricTap?.call(WeatherMetricType.humidity),
                ),
                Container(
                  width: 1,
                  height: 44,
                  color: Colors.white.withValues(alpha: 0.18),
                ),

                // Lượng mưa
                _buildMetricColumn(
                  context: context,
                  icon: WeatherMetricType.rainfall.icon,
                  label: 'Lượng mưa',
                  value: '${current.rainfall.toStringAsFixed(1)} mm',
                  subText: WeatherUnitHelper.getRainfallAssessment(current.rainfall),
                  onTap: () => onMetricTap?.call(WeatherMetricType.rainfall),
                ),
                Container(
                  width: 1,
                  height: 44,
                  color: Colors.white.withValues(alpha: 0.18),
                ),

                // Tốc độ gió
                _buildMetricColumn(
                  context: context,
                  icon: Icons.air_rounded,
                  label: 'Tốc độ gió',
                  value: '${current.windSpeed.toStringAsFixed(1)} km/h',
                  subText: WeatherUnitHelper.getWindAssessment(current.windSpeed),
                  onTap: () => onMetricTap?.call(WeatherMetricType.windSpeed),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required String subText,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 13,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
