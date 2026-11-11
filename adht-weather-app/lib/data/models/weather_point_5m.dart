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

  /// Lọc lấy mẫu danh sách điểm đo theo khoảng thời gian phút (ví dụ 15, 30, 60 phút)
  /// Đảm bảo luôn giữ điểm cuối cùng để biểu đồ hiển thị đến thời điểm gần nhất
  static List<WeatherPoint5m> sampleByInterval(
    List<WeatherPoint5m> points,
    int intervalMinutes,
  ) {
    if (points.length <= 2 || intervalMinutes <= 5) return points;
    final List<WeatherPoint5m> sampled = [];
    int? lastMinute;
    for (final p in points) {
      if (lastMinute == null ||
          (p.minutesFromMidnight - lastMinute).abs() >= intervalMinutes - 2) {
        sampled.add(p);
        lastMinute = p.minutesFromMidnight;
      }
    }
    if (points.isNotEmpty && sampled.isNotEmpty && sampled.last != points.last) {
      sampled.add(points.last);
    }
    return sampled;
  }

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
