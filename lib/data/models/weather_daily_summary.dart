/// Thực thể tổng hợp ngày (Daily Summary) trong chuỗi 7 ngày gần nhất
class WeatherDailySummary {
  final DateTime date;
  final String dayOfWeek; // 'T2', 'T3', ..., 'CN', 'Hôm nay'
  final double avgTemperature; // °C
  final double minTemperature; // °C
  final double maxTemperature; // °C
  final double avgHumidity; // %
  final double totalRainfall; // mm (tổng tích lũy trong ngày)
  final double avgWindSpeed; // km/h

  const WeatherDailySummary({
    required this.date,
    required this.dayOfWeek,
    required this.avgTemperature,
    required this.minTemperature,
    required this.maxTemperature,
    required this.avgHumidity,
    required this.totalRainfall,
    required this.avgWindSpeed,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': date.toIso8601String(),
      'day_of_week': dayOfWeek,
      'avg_temperature': avgTemperature,
      'min_temperature': minTemperature,
      'max_temperature': maxTemperature,
      'avg_humidity': avgHumidity,
      'total_rainfall': totalRainfall,
      'avg_wind_speed': avgWindSpeed,
    };
  }

  factory WeatherDailySummary.fromMap(Map<String, dynamic> map) {
    return WeatherDailySummary(
      date: DateTime.parse(map['date'] as String),
      dayOfWeek: map['day_of_week'] as String,
      avgTemperature: (map['avg_temperature'] as num).toDouble(),
      minTemperature: (map['min_temperature'] as num).toDouble(),
      maxTemperature: (map['max_temperature'] as num).toDouble(),
      avgHumidity: (map['avg_humidity'] as num).toDouble(),
      totalRainfall: (map['total_rainfall'] as num).toDouble(),
      avgWindSpeed: (map['avg_wind_speed'] as num).toDouble(),
    );
  }
}
