/// Thực thể tổng hợp ngày (Daily Summary) trong chuỗi 7 ngày gần nhất
class WeatherDailySummary {
  final DateTime date;
  final String dayOfWeek; // 'T2', 'T3', ..., 'CN', 'Hôm nay'
  final double avgTemperature; // °C
  final double minTemperature; // °C
  final double maxTemperature; // °C
  final double avgHumidity; // %
  final double totalRainfall; // mm (tổng tích lũy trong ngày)
  final bool
  hasRainfallAmount; // false nếu chỉ có dữ liệu legacy không có rainfall_mm
  final String? rainQuality; // 'observed' | 'estimated' | 'unknown'
  final double avgWindSpeed; // m/s
  final bool hasData;
  final bool isPartial;
  final bool isCutoverDay;

  const WeatherDailySummary({
    required this.date,
    required this.dayOfWeek,
    required this.avgTemperature,
    required this.minTemperature,
    required this.maxTemperature,
    required this.avgHumidity,
    required this.totalRainfall,
    this.hasRainfallAmount = true,
    this.rainQuality,
    required this.avgWindSpeed,
    this.hasData = true,
    this.isPartial = false,
    this.isCutoverDay = false,
  });

  /// Tạo bản ghi cho ngày không có dữ liệu đo đạc (None)
  factory WeatherDailySummary.empty({
    required DateTime date,
    required String dayLabel,
  }) {
    return WeatherDailySummary(
      date: date,
      dayOfWeek: dayLabel,
      avgTemperature: 0.0,
      minTemperature: 0.0,
      maxTemperature: 0.0,
      avgHumidity: 0.0,
      totalRainfall: 0.0,
      hasRainfallAmount: false,
      rainQuality: null,
      avgWindSpeed: 0.0,
      hasData: false,
    );
  }
}
