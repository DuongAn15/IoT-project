import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/mock_weather_repository.dart';
import '../data/repositories/weather_repository.dart';
import 'weather_dashboard_state.dart';

/// Provider cung cấp WeatherRepository (mặc định MockWeatherRepository ở giai đoạn UI-First)
final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return MockWeatherRepository();
});

/// AsyncNotifier quản lý trạng thái tải dữ liệu và làm mới cho Dashboard
class WeatherDashboardNotifier extends AsyncNotifier<WeatherDashboardState> {
  @override
  Future<WeatherDashboardState> build() async {
    return _fetchData();
  }

  Future<WeatherDashboardState> _fetchData() async {
    final repo = ref.read(weatherRepositoryProvider);

    final currentFuture = repo.getCurrentWeather();
    final intraDayFuture = repo.getIntraDayData5m();
    final weeklyFuture = repo.get7DaysSummary();

    final results = await Future.wait([
      currentFuture,
      intraDayFuture,
      weeklyFuture,
    ]);

    return WeatherDashboardState(
      current: results[0] as dynamic,
      intraDayPoints: results[1] as dynamic,
      weeklySummaries: results[2] as dynamic,
      lastUpdated: DateTime.now(),
      isOffline: false,
    );
  }

  /// Làm mới dữ liệu khi người dùng kích hoạt Pull-to-refresh
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(weatherRepositoryProvider);
      await repo.refreshAllData();
      return _fetchData();
    });
  }

  /// Chuyển đổi sang trạm quan trắc khác
  Future<void> changeStation(String newStation) async {
    final prev = state.value;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(weatherRepositoryProvider);
      await repo.refreshAllData();
      final fresh = await _fetchData();
      final updatedCurrent = (prev?.current ?? fresh.current).copyWith(
        stationName: newStation,
      );
      return fresh.copyWith(current: updatedCurrent);
    });
  }
}

final weatherDashboardProvider =
    AsyncNotifierProvider<WeatherDashboardNotifier, WeatherDashboardState>(() {
  return WeatherDashboardNotifier();
});
