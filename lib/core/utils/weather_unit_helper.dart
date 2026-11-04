import 'dart:math';
import 'package:flutter/material.dart';

/// Cấu hình trục tung (Y-axis) chuẩn hóa cho biểu đồ
class YAxisConfig {
  final double minY;
  final double maxY;
  final double interval;

  const YAxisConfig({
    required this.minY,
    required this.maxY,
    required this.interval,
  });
}

/// Các loại cảm biến cốt lõi
enum WeatherMetricType {
  temperature,
  humidity,
  rainfall,
  windSpeed;

  String get labelVi {
    switch (this) {
      case WeatherMetricType.temperature:
        return 'Nhiệt độ';
      case WeatherMetricType.humidity:
        return 'Độ ẩm';
      case WeatherMetricType.rainfall:
        return 'Lượng mưa';
      case WeatherMetricType.windSpeed:
        return 'Tốc độ gió';
    }
  }

  String get unit {
    switch (this) {
      case WeatherMetricType.temperature:
        return '°C';
      case WeatherMetricType.humidity:
        return '%';
      case WeatherMetricType.rainfall:
        return 'mm';
      case WeatherMetricType.windSpeed:
        return 'km/h';
    }
  }

  IconData get icon {
    switch (this) {
      case WeatherMetricType.temperature:
        return Icons.thermostat_rounded;
      case WeatherMetricType.humidity:
        return Icons.water_drop_rounded;
      case WeatherMetricType.rainfall:
        return Icons.cloudy_snowing;
      case WeatherMetricType.windSpeed:
        return Icons.air_rounded;
    }
  }
}

/// Tiện ích hỗ trợ hiển thị giá trị, đơn vị và phân cấp định tính
abstract class WeatherUnitHelper {
  static const String tempUnit = '°C';
  static const String humidityUnit = '%';
  static const String rainUnit = 'mm';
  static const String windUnit = 'km/h';

  static String formatTemp(double temp) => '${temp.toStringAsFixed(1)}$tempUnit';
  static String formatHumidity(double humidity) => '${humidity.toStringAsFixed(0)}$humidityUnit';
  static String formatRain(double rain) => '${rain.toStringAsFixed(1)} $rainUnit';
  static String formatWind(double wind) => '${wind.toStringAsFixed(1)} $windUnit';

  /// Đánh giá cảm nhận nhiệt độ
  static String getTemperatureAssessment(double temp) {
    if (temp < 18) return 'Lạnh';
    if (temp < 24) return 'Mát mẻ';
    if (temp <= 32) return 'Ấm áp & Dễ chịu';
    if (temp <= 36) return 'Oi bức';
    return 'Nắng nóng gay gắt';
  }

  /// Đánh giá mức độ ẩm
  static String getHumidityAssessment(double humidity) {
    if (humidity < 40) return 'Khô ráo';
    if (humidity <= 70) return 'Dễ chịu';
    if (humidity <= 85) return 'Khá ẩm';
    return 'Ẩm ướt cao';
  }

  /// Đánh giá lượng mưa
  static String getRainfallAssessment(double rainfall) {
    if (rainfall <= 0.0) return 'Không mưa';
    if (rainfall < 2.0) return 'Mưa phùn / Mưa nhẹ';
    if (rainfall < 10.0) return 'Mưa rào vừa';
    if (rainfall < 30.0) return 'Mưa to';
    return 'Mưa rất to';
  }

  /// Đánh giá cấp gió Beaufort ước lượng (chỉ hiển thị cấp gió)
  static String getWindAssessment(double windSpeed) {
    if (windSpeed < 2.0) return 'Cấp 0';
    if (windSpeed < 6.0) return 'Cấp 1';
    if (windSpeed < 12.0) return 'Cấp 2';
    if (windSpeed < 20.0) return 'Cấp 3';
    if (windSpeed < 29.0) return 'Cấp 4';
    if (windSpeed < 39.0) return 'Cấp 5';
    return 'Cấp 6+';
  }

  /// Tổng hợp mô tả tổng quan trạng thái thời tiết
  static String getOverallWeatherStatus({
    required double temp,
    required double rain,
    required double wind,
  }) {
    if (rain > 5.0) return 'Trời đang có mưa rào';
    if (rain > 0.0) return 'Trời có mưa nhỏ lác đác';
    if (wind > 25.0) return 'Trời nhiều gió lộng';
    if (temp >= 33.0) return 'Trời nắng nóng';
    if (temp <= 22.0) return 'Trời mát mẻ se lạnh';
    return 'Thời tiết ôn hòa dễ chịu';
  }

  /// Icon đại diện thời tiết dựa trên các chỉ số
  static IconData getOverallWeatherIcon({
    required double temp,
    required double rain,
    required double wind,
  }) {
    if (rain > 5.0) return Icons.thunderstorm_rounded;
    if (rain > 0.0) return Icons.cloudy_snowing;
    if (wind > 25.0) return Icons.air_rounded;
    if (temp >= 33.0) return Icons.wb_sunny_rounded;
    if (temp <= 22.0) return Icons.cloud_rounded;
    return Icons.wb_cloudy_rounded;
  }

  /// Tính toán cấu hình trục Y chuẩn hóa: luôn bắt đầu từ 0 và chia các khoảng đều chẵn
  static YAxisConfig calculateYAxisConfig({
    required WeatherMetricType metricType,
    required double dataMax,
    bool isCompact = false,
  }) {
    const minY = 0.0;
    double interval = 10.0;
    double maxY = 40.0;

    switch (metricType) {
      case WeatherMetricType.temperature:
        if (dataMax <= 20) {
          interval = 5.0;
        } else if (dataMax <= 40) {
          interval = 10.0;
        } else {
          interval = 10.0;
        }
        maxY = (dataMax / interval).ceil() * interval;
        if (dataMax >= maxY - (interval * 0.2)) {
          maxY += interval;
        }
        maxY = max(interval * 2, maxY);
        break;

      case WeatherMetricType.humidity:
        // Độ ẩm luôn từ 0% đến 100%, chia đều 4 khoảng 25% (0, 25, 50, 75, 100)
        interval = 25.0;
        maxY = 100.0;
        break;

      case WeatherMetricType.windSpeed:
        if (dataMax <= 15) {
          interval = 5.0;
        } else if (dataMax <= 35) {
          interval = 10.0;
        } else if (dataMax <= 70) {
          interval = 20.0;
        } else {
          interval = 25.0;
        }
        maxY = (dataMax / interval).ceil() * interval;
        if (dataMax >= maxY - (interval * 0.2)) {
          maxY += interval;
        }
        maxY = max(interval * 2, maxY);
        break;

      case WeatherMetricType.rainfall:
        if (dataMax <= 5) {
          interval = 2.0;
        } else if (dataMax <= 15) {
          interval = 5.0;
        } else if (dataMax <= 40) {
          interval = 10.0;
        } else if (dataMax <= 80) {
          interval = 20.0;
        } else {
          interval = 25.0;
        }
        maxY = (dataMax / interval).ceil() * interval;
        if (dataMax >= maxY - (interval * 0.2)) {
          maxY += interval;
        }
        maxY = max(interval * 2, maxY);
        break;
    }

    return YAxisConfig(
      minY: minY,
      maxY: maxY,
      interval: interval,
    );
  }
}
