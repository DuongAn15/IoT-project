import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import '../data/database/weather_monitoring_dao.dart';

/// Provider cung cấp thể hiện cơ sở dữ liệu SQLite cục bộ
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase.instance;
});

/// Provider cung cấp DAO thao tác với bảng `weather_monitoring`
final weatherMonitoringDaoProvider = Provider<WeatherMonitoringDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return WeatherMonitoringDao(db);
});
