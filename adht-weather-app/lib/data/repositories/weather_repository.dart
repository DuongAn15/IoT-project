import '../models/weather_current_model.dart';
import '../models/weather_point.dart';
import '../models/weather_daily_summary.dart';

/// Interface trừu tượng định nghĩa hợp đồng dữ liệu cho toàn bộ ứng dụng
abstract class WeatherRepository {
  /// Lấy bản ghi thời tiết mới nhất
  Future<WeatherCurrentModel> getCurrentWeather();

  /// Lấy danh sách điểm đo trong ngày (từ 00:00 đến hiện tại)
  Future<List<WeatherPoint>> getIntraDayData();

  /// Lấy danh sách tổng hợp 7 ngày gần nhất (trung bình ngày & tổng lượng mưa)
  Future<List<WeatherDailySummary>> get7DaysSummary();

  /// Làm mới toàn bộ dữ liệu (khi người dùng thực hiện Pull-to-refresh)
  Future<void> refreshAllData();
}
