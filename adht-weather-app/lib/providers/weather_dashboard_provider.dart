import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/network/weather_api_service.dart';
import '../data/repositories/app_weather_repository.dart';
import '../data/repositories/weather_repository.dart';
import 'database_provider.dart';
import 'device_settings_provider.dart';
import 'weather_dashboard_state.dart';

/// Provider cung cấp dịch vụ mạng WeatherApiService
final weatherApiServiceProvider = Provider<WeatherApiService>((ref) {
  final dioClient = ref.watch(dioClientProvider);
  return WeatherApiService(dioClient);
});

/// Provider cung cấp WeatherRepository kết nối dữ liệu thực, SQLite cache và file cache
final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  final apiService = ref.watch(weatherApiServiceProvider);
  final dao = ref.watch(weatherMonitoringDaoProvider);
  final fileStorage = ref.watch(latestWeatherFileStorageProvider);
  final selectedStationId = ref.watch(selectedDeviceIdProvider);

  return AppWeatherRepository(
    apiService: apiService,
    dao: dao,
    fileStorage: fileStorage,
    currentDeviceId: selectedStationId,
  );
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
    final intraDayFuture = repo.getIntraDayData();
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
