import '../../core/utils/date_time_formatter.dart';
import 'weather_point.dart';

/// Đại diện cho một bản ghi quan trắc lưu trong bảng SQLite `weather_monitoring`
class WeatherMonitoringRecord {
  final int? id;
  final String deviceId;
  final double temperature; // °C
  final double humidity; // %
  final double rainfall; // rain_rate (mm/h)
  final double? rainfallMm; // Bucket rainfall amount (mm)
  final double windSpeed; // km/h
  final String? source; // 'v2' | 'v1_legacy'
  final String? rainQuality; // 'observed' | 'estimated'
  final int? sampleCount;
  final double? tempMin;
  final double? tempMax;
  final DateTime recordedAt;
  final int timestamp; // millisecondsSinceEpoch

  WeatherMonitoringRecord({
    this.id,
    required this.deviceId,
    required this.temperature,
    required this.humidity,
    required this.rainfall,
    this.rainfallMm,
    required this.windSpeed,
    this.source,
    this.rainQuality,
    this.sampleCount,
    this.tempMin,
    this.tempMax,
    required this.recordedAt,
    int? timestamp,
  }) : timestamp = timestamp ?? recordedAt.millisecondsSinceEpoch;

  /// Chuyển sang Map để insert vào SQLite
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'device_id': deviceId,
      'temperature': temperature,
      'humidity': humidity,
      'rainfall': rainfall,
      if (rainfallMm != null) 'rainfall_mm': rainfallMm,
      'wind_speed': windSpeed,
      if (source != null) 'source': source,
      if (rainQuality != null) 'rain_quality': rainQuality,
      if (sampleCount != null) 'sample_count': sampleCount,
      if (tempMin != null) 'temp_min': tempMin,
      if (tempMax != null) 'temp_max': tempMax,
      // Lưu ISO8601 chuẩn UTC nguyên bản vào SQLite
      'recorded_at': recordedAt.toUtc().toIso8601String(),
      'timestamp': timestamp,
    };
  }

  /// Khởi tạo từ Map đọc từ SQLite (tự động chuyển đổi UTC sang giờ thiết bị qua .toLocal())
  factory WeatherMonitoringRecord.fromMap(Map<String, dynamic> map) {
    final recordedAtRaw = map['recorded_at'];
    final tsRaw = map['timestamp'] as int?;

    DateTime parsedDate;
    if (recordedAtRaw != null) {
      parsedDate = DateTimeFormatter.parseUtcToLocal(recordedAtRaw);
    } else if (tsRaw != null) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(tsRaw).toLocal();
    } else {
      parsedDate = DateTime.now();
    }

    return WeatherMonitoringRecord(
      id: map['id'] as int?,
      deviceId: map['device_id'] as String? ?? 'adht_weather_01',
      temperature: (map['temperature'] as num).toDouble(),
      humidity: (map['humidity'] as num).toDouble(),
      rainfall: (map['rainfall'] as num).toDouble(),
      rainfallMm: (map['rainfall_mm'] as num?)?.toDouble(),
      windSpeed: (map['wind_speed'] as num).toDouble(),
      source: map['source'] as String?,
      rainQuality: map['rain_quality'] as String?,
      sampleCount: (map['sample_count'] as num?)?.toInt(),
      tempMin: (map['temp_min'] as num?)?.toDouble(),
      tempMax: (map['temp_max'] as num?)?.toDouble(),
      recordedAt: parsedDate,
      timestamp: tsRaw ?? parsedDate.millisecondsSinceEpoch,
    );
  }

  /// Khởi tạo từ phần tử JSON của Backend API (`/api/weather/history` hoặc `/api/weather/latest`)
  /// Dữ liệu Backend là UTC (GMT+0) -> tự động chuyển đổi sang múi giờ thiết bị qua .toLocal()
  factory WeatherMonitoringRecord.fromJson(
    Map<String, dynamic> json, {
    String defaultDeviceId = 'adht_weather_01',
  }) {
    final date = DateTimeFormatter.parseUtcToLocal(json['recorded_at']);

    return WeatherMonitoringRecord(
      deviceId: json['device_id'] as String? ?? defaultDeviceId,
      temperature: (json['temp'] as num?)?.toDouble() ?? 0.0,
      humidity: (json['humi'] as num?)?.toDouble() ?? 0.0,
      rainfall: (json['rain_rate'] as num?)?.toDouble() ?? 0.0,
      rainfallMm: (json['rainfall_mm'] as num?)?.toDouble(),
      windSpeed: (json['wind_speed'] as num?)?.toDouble() ?? 0.0,
      source: json['source'] as String?,
      rainQuality: json['rain_quality'] as String?,
      sampleCount: (json['sample_count'] as num?)?.toInt(),
      tempMin: (json['temp_min'] as num?)?.toDouble(),
      tempMax: (json['temp_max'] as num?)?.toDouble(),
      recordedAt: date,
      timestamp: date.millisecondsSinceEpoch,
    );
  }

  /// Chuyển đổi sang WeatherPoint cho các biểu đồ fl_chart
  WeatherPoint toWeatherPoint() {
    return WeatherPoint(
      timestamp: recordedAt,
      temperature: temperature,
      humidity: humidity,
      rainfall: rainfall,
      windSpeed: windSpeed,
    );
  }

  @override
  String toString() {
    return 'WeatherMonitoringRecord(id: $id, deviceId: $deviceId, '
        'temp: $temperature, humi: $humidity, rain: $rainfall, '
        'wind: $windSpeed, recordedAt: $recordedAt, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WeatherMonitoringRecord &&
        other.deviceId == deviceId &&
        other.timestamp == timestamp &&
        other.temperature == temperature &&
        other.humidity == humidity &&
        other.rainfall == rainfall &&
        other.windSpeed == windSpeed;
  }

  @override
  int get hashCode {
    return Object.hash(
      deviceId,
      timestamp,
      temperature,
      humidity,
      rainfall,
      windSpeed,
    );
  }
}
