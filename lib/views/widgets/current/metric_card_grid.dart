import 'package:flutter/material.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/weather_unit_helper.dart';
import '../../../data/models/weather_current_model.dart';
import 'single_metric_tile.dart';

/// Lưới 2x2 hiển thị trọn vẹn 4 thông số cảm biến cốt lõi
class MetricCardGrid extends StatelessWidget {
  final WeatherCurrentModel current;
  final Function(WeatherMetricType)? onMetricTap;

  const MetricCardGrid({
    super.key,
    required this.current,
    this.onMetricTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: AppDimensions.spaceMd,
      mainAxisSpacing: AppDimensions.spaceMd,
      childAspectRatio: 1.35,
      children: [
        // 1. Nhiệt độ
        SingleMetricTile(
          type: WeatherMetricType.temperature,
          value: current.temperature,
          assessment: WeatherUnitHelper.getTemperatureAssessment(current.temperature),
          onTap: () => onMetricTap?.call(WeatherMetricType.temperature),
        ),

        // 2. Độ ẩm
        SingleMetricTile(
          type: WeatherMetricType.humidity,
          value: current.humidity,
          assessment: WeatherUnitHelper.getHumidityAssessment(current.humidity),
          onTap: () => onMetricTap?.call(WeatherMetricType.humidity),
        ),

        // 3. Lượng mưa
        SingleMetricTile(
          type: WeatherMetricType.rainfall,
          value: current.rainfall,
          assessment: WeatherUnitHelper.getRainfallAssessment(current.rainfall),
          onTap: () => onMetricTap?.call(WeatherMetricType.rainfall),
        ),

        // 4. Tốc độ gió
        SingleMetricTile(
          type: WeatherMetricType.windSpeed,
          value: current.windSpeed,
          assessment: WeatherUnitHelper.getWindAssessment(current.windSpeed),
          onTap: () => onMetricTap?.call(WeatherMetricType.windSpeed),
        ),
      ],
    );
  }
}
