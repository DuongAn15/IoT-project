import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/weather_unit_helper.dart';
import '../../../data/models/weather_current_model.dart';

/// Thẻ Anh Hùng Thời Tiết Hợp Nhất (Unified Hero Weather Card)
/// Nhiệt độ hiển thị lớn tại trung tâm, thông số Thấp/Cao cùng dòng bên dưới, cùng 3 chỉ số cảm biến.
class HeroWeatherCard extends StatelessWidget {
  final WeatherCurrentModel current;
  final double? minTemp;
  final double? maxTemp;

  const HeroWeatherCard({
    super.key,
    required this.current,
    this.minTemp,
    this.maxTemp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimensions.spaceMd,
        vertical: AppDimensions.spaceLg,
      ),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Nhiệt độ lớn ở trung tâm card & Thấp / Cao ngay dưới cùng dòng
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
            child: Column(
              children: [
                // Số nhiệt độ lớn ở chính giữa
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      current.temperature.toStringAsFixed(1),
                      style: theme.textTheme.displayLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 68,
                        letterSpacing: -1.5,
                      ),
                    ),
                    Text(
                      '°C',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                        fontSize: 28,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Thấp và Cao nằm ngay dưới nhiệt độ, cùng một dòng cách nhau một khoảng
                if (minTemp != null && maxTemp != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Thấp: ${minTemp!.toStringAsFixed(1)}°',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: AppDimensions.spaceXl), // Khoảng cách giữa Thấp và Cao
                      Text(
                        'Cao: ${maxTemp!.toStringAsFixed(1)}°',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.spaceLg),

          // 2. Khối 3 chỉ số cảm biến (Độ ẩm, Lượng mưa, Tốc độ gió) trong cùng khối
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
                  icon: WeatherMetricType.humidity.icon,
                  label: 'Độ ẩm',
                  value: '${current.humidity.toStringAsFixed(0)}%',
                  subText: WeatherUnitHelper.getHumidityAssessment(current.humidity),
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
                ),
                Container(
                  width: 1,
                  height: 44,
                  color: Colors.white.withValues(alpha: 0.18),
                ),

                // Tốc độ gió
                _buildMetricColumn(
                  context: context,
                  icon: WeatherMetricType.windSpeed.icon,
                  label: 'Tốc độ gió',
                  value: '${current.windSpeed.toStringAsFixed(1)} km/h',
                  subText: WeatherUnitHelper.getWindAssessment(current.windSpeed),
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
  }) {
    final theme = Theme.of(context);

    return Expanded(
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
    );
  }
}
