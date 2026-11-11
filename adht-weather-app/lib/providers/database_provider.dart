import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import '../data/database/weather_monitoring_dao.dart';
import '../data/storage/latest_weather_file_storage.dart';

/// Provider cung cấp thể hiện cơ sở dữ liệu SQLite cục bộ
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

/// Provider cung cấp DAO thao tác với 2 bảng `weather_inday` và `weather_week`
final weatherMonitoringDaoProvider = Provider<WeatherMonitoringDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return WeatherMonitoringDao(db);
});

/// Provider cung cấp nơi lưu trữ file cục bộ cho bản ghi thời tiết mới nhất (Latest)
final latestWeatherFileStorageProvider = Provider<LatestWeatherFileStorage>((ref) {
  return LatestWeatherFileStorage();
});
