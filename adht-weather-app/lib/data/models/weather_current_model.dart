import '../models/weather_point_5m.dart';

/// Thực thể dữ liệu thời tiết tức thời đo đạc mới nhất
class WeatherCurrentModel {
  final String stationId;
  final String stationName;
  final DateTime timestamp;
  final double temperature; // °C
  final double humidity; // %
  final double rainfall; // mm
  final double windSpeed; // km/h
  final bool isOnline;

  const WeatherCurrentModel({
    required this.stationId,
    required this.stationName,
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.rainfall,
    required this.windSpeed,
    this.isOnline = true,
  });

  WeatherCurrentModel copyWith({
    String? stationId,
    String? stationName,
    DateTime? timestamp,
    double? temperature,
    double? humidity,
    double? rainfall,
    double? windSpeed,
    bool? isOnline,
  }) {
    return WeatherCurrentModel(
      stationId: stationId ?? this.stationId,
      stationName: stationName ?? this.stationName,
      timestamp: timestamp ?? this.timestamp,
      temperature: temperature ?? this.temperature,
      humidity: humidity ?? this.humidity,
      rainfall: rainfall ?? this.rainfall,
      windSpeed: windSpeed ?? this.windSpeed,
      isOnline: isOnline ?? this.isOnline,
    );
  }

  /// Chuyển đổi từ WeatherPoint5m
  factory WeatherCurrentModel.fromPoint5m({
    required WeatherPoint5m point,
    String stationId = 'STATION_001',
    String stationName = 'Trạm Quan Trắc IoT Trung Tâm',
    bool isOnline = true,
  }) {
    return WeatherCurrentModel(
      stationId: stationId,
      stationName: stationName,
      timestamp: point.timestamp,
      temperature: point.temperature,
      humidity: point.humidity,
      rainfall: point.rainfall,
      windSpeed: point.windSpeed,
      isOnline: isOnline,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'station_id': stationId,
      'station_name': stationName,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'temperature': temperature,
      'humidity': humidity,
      'rainfall': rainfall,
      'wind_speed': windSpeed,
      'is_online': isOnline ? 1 : 0,
    };
  }

  factory WeatherCurrentModel.fromMap(Map<String, dynamic> map) {
    return WeatherCurrentModel(
      stationId: map['station_id'] as String? ?? 'STATION_001',
      stationName: map['station_name'] as String? ?? 'Trạm Quan Trắc IoT',
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      temperature: (map['temperature'] as num).toDouble(),
      humidity: (map['humidity'] as num).toDouble(),
      rainfall: (map['rainfall'] as num).toDouble(),
      windSpeed: (map['wind_speed'] as num).toDouble(),
      isOnline: (map['is_online'] as int? ?? 1) == 1,
    );
  }
}
