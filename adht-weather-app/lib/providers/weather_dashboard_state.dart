import '../data/models/weather_current_model.dart';
import '../data/models/weather_daily_summary.dart';
import '../data/models/weather_point.dart';

/// Lớp trạng thái đóng gói toàn bộ dữ liệu giao diện Dashboard
class WeatherDashboardState {
  final WeatherCurrentModel current;
  final List<WeatherPoint> intraDayPoints;
  final List<WeatherDailySummary> weeklySummaries;
  final DateTime lastUpdated;
  final bool isOffline;

  const WeatherDashboardState({
    required this.current,
    required this.intraDayPoints,
    required this.weeklySummaries,
    required this.lastUpdated,
    this.isOffline = false,
  });

  WeatherDashboardState copyWith({
    WeatherCurrentModel? current,
    List<WeatherPoint>? intraDayPoints,
    List<WeatherDailySummary>? weeklySummaries,
    DateTime? lastUpdated,
    bool? isOffline,
  }) {
    return WeatherDashboardState(
      current: current ?? this.current,
      intraDayPoints: intraDayPoints ?? this.intraDayPoints,
      weeklySummaries: weeklySummaries ?? this.weeklySummaries,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      isOffline: isOffline ?? this.isOffline,
    );
  }
}
