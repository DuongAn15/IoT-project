import 'weather_point_5m.dart';

/// Đại diện cho một bản ghi quan trắc lưu trong bảng SQLite `weather_monitoring`
class WeatherMonitoringRecord {
  final int? id;
  final String deviceId;
  final double temperature; // °C
  final double humidity; // %
  final double rainfall; // mm / rain_rate
  final double windSpeed; // km/h
  final DateTime recordedAt;
  final int timestamp; // millisecondsSinceEpoch

  WeatherMonitoringRecord({
    this.id,
    required this.deviceId,
    required this.temperature,
    required this.humidity,
    required this.rainfall,
    required this.windSpeed,
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
      'wind_speed': windSpeed,
      'recorded_at': recordedAt.toUtc().toIso8601String(),
      'timestamp': timestamp,
    };
  }

  /// Khởi tạo từ Map đọc từ SQLite
  factory WeatherMonitoringRecord.fromMap(Map<String, dynamic> map) {
    final recordedAtRaw = map['recorded_at'];
    final tsRaw = map['timestamp'] as int?;

    DateTime parsedDate;
    if (recordedAtRaw is String) {
      parsedDate = DateTime.parse(recordedAtRaw).toLocal();
    } else if (tsRaw != null) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(tsRaw);
    } else {
      parsedDate = DateTime.now();
    }

    return WeatherMonitoringRecord(
      id: map['id'] as int?,
      deviceId: map['device_id'] as String? ?? 'adht_weather_01',
      temperature: (map['temperature'] as num).toDouble(),
      humidity: (map['humidity'] as num).toDouble(),
      rainfall: (map['rainfall'] as num).toDouble(),
      windSpeed: (map['wind_speed'] as num).toDouble(),
      recordedAt: parsedDate,
      timestamp: tsRaw ?? parsedDate.millisecondsSinceEpoch,
    );
  }

  /// Khởi tạo từ phần tử JSON của Backend API (`/api/weather/history` hoặc `/api/weather/latest`)
  factory WeatherMonitoringRecord.fromJson(
    Map<String, dynamic> json, {
    String defaultDeviceId = 'adht_weather_01',
  }) {
    final recordedAtStr = json['recorded_at'] as String?;
    final date = recordedAtStr != null
        ? DateTime.parse(recordedAtStr).toLocal()
        : DateTime.now();

    return WeatherMonitoringRecord(
      deviceId: json['device_id'] as String? ?? defaultDeviceId,
      temperature: (json['temp'] as num?)?.toDouble() ?? 0.0,
      humidity: (json['humi'] as num?)?.toDouble() ?? 0.0,
      rainfall: (json['rain_rate'] as num?)?.toDouble() ?? 0.0,
      windSpeed: (json['wind_speed'] as num?)?.toDouble() ?? 0.0,
      recordedAt: date,
      timestamp: date.millisecondsSinceEpoch,
    );
  }

  /// Chuyển đổi sang WeatherPoint5m cho các biểu đồ fl_chart
  WeatherPoint5m toWeatherPoint5m() {
    return WeatherPoint5m(
      timestamp: recordedAt,
      temperature: temperature,
      humidity: humidity,
      rainfall: rainfall,
      windSpeed: windSpeed,
    );
  }

  WeatherMonitoringRecord copyWith({
    int? id,
    String? deviceId,
    double? temperature,
    double? humidity,
    double? rainfall,
    double? windSpeed,
    DateTime? recordedAt,
    int? timestamp,
  }) {
    return WeatherMonitoringRecord(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      rainfall: rainfall ?? this.rainfall,
      windSpeed: windSpeed ?? this.windSpeed,
      recordedAt: recordedAt ?? this.recordedAt,
      timestamp: timestamp ?? this.timestamp,
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
