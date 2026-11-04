/// Biểu diễn một điểm đo tại mốc 5 phút
class WeatherPoint5m {
  final DateTime timestamp;
  final double temperature; // °C
  final double humidity; // %
  final double rainfall; // mm
  final double windSpeed; // km/h

  const WeatherPoint5m({
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.rainfall,
    required this.windSpeed,
  });

  /// Số phút tính từ 00:00 của ngày (0 .. 1440)
  /// Sử dụng làm tọa độ X trên fl_chart LineChart/BarChart
  int get minutesFromMidnight => timestamp.hour * 60 + timestamp.minute;

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch,
      'temperature': temperature,
      'humidity': humidity,
      'rainfall': rainfall,
      'wind_speed': windSpeed,
    };
  }

  factory WeatherPoint5m.fromMap(Map<String, dynamic> map) {
    return WeatherPoint5m(
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      temperature: (map['temperature'] as num).toDouble(),
      humidity: (map['humidity'] as num).toDouble(),
      rainfall: (map['rainfall'] as num).toDouble(),
      windSpeed: (map['wind_speed'] as num).toDouble(),
    );
  }
}
