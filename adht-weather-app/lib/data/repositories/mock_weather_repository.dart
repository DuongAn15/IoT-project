import '../mock/mock_weather_data.dart';
import '../models/weather_current_model.dart';
import '../models/weather_daily_summary.dart';
import '../models/weather_point_5m.dart';
import 'weather_repository.dart';

/// Triển khai MockWeatherRepository phục vụ giai đoạn UI-First
/// Tách biệt hoàn toàn tầng UI khỏi nguồn dữ liệu thật.
class MockWeatherRepository implements WeatherRepository {
  List<WeatherPoint5m>? _cachedIntraDay;
  WeatherCurrentModel? _cachedCurrent;
  List<WeatherDailySummary>? _cached7Days;

  @override
  Future<WeatherCurrentModel> getCurrentWeather() async {
    if (_cachedCurrent != null) return _cachedCurrent!;
    // Giả lập độ trễ mạng nhẹ khi mở app
    await Future.delayed(const Duration(milliseconds: 200));
    _cachedIntraDay ??= MockWeatherDataGenerator.generateIntraDay5m();
    _cachedCurrent = MockWeatherDataGenerator.generateCurrentWeather(points: _cachedIntraDay);
    return _cachedCurrent!;
  }

  @override
  Future<List<WeatherPoint5m>> getIntraDayData5m() async {
    if (_cachedIntraDay != null) return _cachedIntraDay!;
    await Future.delayed(const Duration(milliseconds: 200));
    _cachedIntraDay = MockWeatherDataGenerator.generateIntraDay5m();
    return _cachedIntraDay!;
  }

  @override
  Future<List<WeatherDailySummary>> get7DaysSummary() async {
    if (_cached7Days != null) return _cached7Days!;
    await Future.delayed(const Duration(milliseconds: 200));
    _cached7Days = MockWeatherDataGenerator.generate7DaysSummary();
    return _cached7Days!;
  }

  @override
  Future<void> refreshAllData() async {
    // Giả lập thời gian làm mới khi vuốt Pull-to-refresh (500ms)
    await Future.delayed(const Duration(milliseconds: 500));
    _cachedIntraDay = MockWeatherDataGenerator.generateIntraDay5m();
    _cachedCurrent = MockWeatherDataGenerator.generateCurrentWeather(points: _cachedIntraDay);
    _cached7Days = MockWeatherDataGenerator.generate7DaysSummary();
  }
}
