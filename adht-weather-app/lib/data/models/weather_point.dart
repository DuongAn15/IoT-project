/// Biểu diễn một điểm đo đạc thời tiết trên biểu đồ (Chart Data Point)
class WeatherPoint {
  final DateTime timestamp;
  final double temperature; // °C
  final double humidity; // %
  final double rainfall; // mm
  final double windSpeed; // km/h

  const WeatherPoint({
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.rainfall,
    required this.windSpeed,
  });

  /// Số phút tính từ 00:00 của ngày (0 .. 1440)
  /// Sử dụng làm tọa độ X trên fl_chart LineChart/BarChart
  int get minutesFromMidnight => timestamp.hour * 60 + timestamp.minute;
}
