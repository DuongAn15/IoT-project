import 'dart:math';
import '../models/weather_current_model.dart';
import '../models/weather_point_5m.dart';
import '../models/weather_daily_summary.dart';
import '../../core/utils/date_time_formatter.dart';

/// Bộ sinh dữ liệu giả lập chân thực phục vụ UI-First
/// Tạo chuỗi dữ liệu mốc 5 phút theo chu kỳ ngày đêm và dữ liệu tổng hợp 7 ngày.
class MockWeatherDataGenerator {
  static final Random _random = Random(42); // Seed cố định để dữ liệu mượt mà, ổn định

  /// Sinh danh sách các mốc 5 phút từ 00:00 đến thời điểm hiện tại của ngày hôm nay
  static List<WeatherPoint5m> generateIntraDay5m() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day, 0, 0);

    // Tính số bước 5 phút từ 00:00 đến hiện tại
    final currentMinutes = now.hour * 60 + now.minute;
    final totalSteps = (currentMinutes ~/ 5) + 1;

    final points = <WeatherPoint5m>[];

    for (int i = 0; i < totalSteps; i++) {
      final pointTime = todayStart.add(Duration(minutes: i * 5));
      final hourFrac = pointTime.hour + (pointTime.minute / 60.0);

      // 1. Chu kỳ nhiệt độ ngày đêm: Thấp nhất lúc 05:30 (~23.5°C), cao nhất lúc 14:00 (~33.0°C)
      // Góc pha dịch chuyển sao cho đỉnh đạt cực đại vào lúc 14h
      final tempAngle = ((hourFrac - 14.0) / 24.0) * 2 * pi;
      final tempBase = 28.0;
      final tempAmplitude = 4.8;
      // Thêm biến động nhỏ ngẫu nhiên +/- 0.3°C
      final tempNoise = (_random.nextDouble() - 0.5) * 0.4;
      final temp = double.parse((tempBase + tempAmplitude * cos(tempAngle) + tempNoise).toStringAsFixed(1));

      // 2. Độ ẩm: Tỷ lệ nghịch với nhiệt độ (cao nhất lúc rạng sáng ~88%, thấp nhất lúc giữa trưa ~52%)
      final humAngle = ((hourFrac - 2.0) / 24.0) * 2 * pi;
      final humBase = 70.0;
      final humAmplitude = 18.0;
      final humNoise = (_random.nextDouble() - 0.5) * 1.5;
      final hum = double.parse((humBase + humAmplitude * cos(humAngle) + humNoise).clamp(35.0, 95.0).toStringAsFixed(0));

      // 3. Lượng mưa: Chủ yếu là 0.0, giả lập cơn mưa rào nhẹ vào khoảng 13:00 - 13:40
      double rain = 0.0;
      if (hourFrac >= 13.0 && hourFrac <= 13.7) {
        final rainPeak = sin((hourFrac - 13.0) / 0.7 * pi);
        rain = double.parse((rainPeak * 3.5 + _random.nextDouble() * 0.8).toStringAsFixed(1));
      }

      // 4. Tốc độ gió: Ban đêm 4-9 km/h, ban ngày 12-22 km/h
      final windBase = 11.0;
      final windAmp = 6.0;
      final windAngle = ((hourFrac - 15.0) / 24.0) * 2 * pi;
      final windNoise = (_random.nextDouble() - 0.5) * 2.0;
      final wind = double.parse((windBase + windAmp * cos(windAngle) + windNoise).clamp(1.5, 35.0).toStringAsFixed(1));

      points.add(WeatherPoint5m(
        timestamp: pointTime,
        temperature: temp,
        humidity: hum,
        rainfall: rain,
        windSpeed: wind,
      ));
    }

    return points;
  }

  /// Lấy bản ghi đo đạc mới nhất (Current Weather)
  static WeatherCurrentModel generateCurrentWeather({List<WeatherPoint5m>? points}) {
    final list = points ?? generateIntraDay5m();
    final latestPoint = list.isNotEmpty
        ? list.last
        : WeatherPoint5m(
            timestamp: DateTime.now(),
            temperature: 28.5,
            humidity: 65.0,
            rainfall: 0.0,
            windSpeed: 12.0,
          );

    return WeatherCurrentModel.fromPoint5m(
      point: latestPoint,
      stationId: 'STATION_001',
      stationName: 'Trạm Quan Trắc IoT Trung Tâm',
      isOnline: true,
    );
  }

  /// Sinh danh sách 7 ngày gần nhất (tính từ 6 ngày trước tới hôm nay)
  static List<WeatherDailySummary> generate7DaysSummary() {
    final now = DateTime.now();
    final list = <WeatherDailySummary>[];

    // Mẫu biến động các ngày trong tuần
    final pastDailyData = [
      {'avgTemp': 26.8, 'minTemp': 22.4, 'maxTemp': 31.0, 'avgHum': 76.0, 'rain': 14.5, 'wind': 10.2},
      {'avgTemp': 27.2, 'minTemp': 23.0, 'maxTemp': 31.5, 'avgHum': 74.0, 'rain': 6.0, 'wind': 12.8},
      {'avgTemp': 28.0, 'minTemp': 23.8, 'maxTemp': 32.4, 'avgHum': 68.0, 'rain': 0.0, 'wind': 14.1},
      {'avgTemp': 28.5, 'minTemp': 24.1, 'maxTemp': 33.2, 'avgHum': 65.0, 'rain': 0.0, 'wind': 15.6},
      {'avgTemp': 29.1, 'minTemp': 24.6, 'maxTemp': 34.0, 'avgHum': 62.0, 'rain': 0.2, 'wind': 11.5},
      {'avgTemp': 28.2, 'minTemp': 23.9, 'maxTemp': 32.8, 'avgHum': 69.0, 'rain': 8.5, 'wind': 16.2},
      {'avgTemp': 28.6, 'minTemp': 24.2, 'maxTemp': 33.0, 'avgHum': 66.0, 'rain': 2.5, 'wind': 13.4},
    ];

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final dayLabel = DateTimeFormatter.getDayOfWeekLabel(date);
      final dataIndex = 6 - i;
      final dayData = pastDailyData[dataIndex];

      list.add(WeatherDailySummary(
        date: date,
        dayOfWeek: dayLabel,
        avgTemperature: (dayData['avgTemp'] as num).toDouble(),
        minTemperature: (dayData['minTemp'] as num).toDouble(),
        maxTemperature: (dayData['maxTemp'] as num).toDouble(),
        avgHumidity: (dayData['avgHum'] as num).toDouble(),
        totalRainfall: (dayData['rain'] as num).toDouble(),
        avgWindSpeed: (dayData['wind'] as num).toDouble(),
      ));
    }

    return list;
  }
}
