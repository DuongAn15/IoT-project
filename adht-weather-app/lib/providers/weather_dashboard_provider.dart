import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/api_constants.dart';
import '../data/models/weather_current_model.dart';
import '../data/models/weather_daily_summary.dart';
import '../data/models/weather_point.dart';
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
  int _activeRequestId = 0;

  @override
  Future<WeatherDashboardState> build() async {
    final targetDeviceId = ref.watch(selectedDeviceIdProvider);
    final repo = ref.watch(weatherRepositoryProvider);
    final requestId = ++_activeRequestId;
    return _fetchDataForStation(repo, targetDeviceId, requestId);
  }

  Future<WeatherDashboardState> _fetchDataForStation(
    WeatherRepository repo,
    String targetDeviceId,
    int requestId,
  ) async {
    final results = await Future.wait([
      repo.getCurrentWeather(),
      repo.getIntraDayData(),
      repo.get7DaysSummary(),
    ]);

    if (requestId != _activeRequestId ||
        ref.read(selectedDeviceIdProvider) != targetDeviceId) {
      throw StateError('Stale weather response discarded for $targetDeviceId');
    }

    final current = results[0] as WeatherCurrentModel;
    return WeatherDashboardState(
      current: current,
      intraDayPoints: results[1] as List<WeatherPoint>,
      weeklySummaries: results[2] as List<WeatherDailySummary>,
      lastUpdated: DateTime.now(),
      isOffline: !current.isOnline,
    );
  }

  /// Làm mới dữ liệu khi người dùng kích hoạt Pull-to-refresh
  Future<void> refresh() async {
    final targetDeviceId = ref.read(selectedDeviceIdProvider);
    final repo = ref.read(weatherRepositoryProvider);
    final requestId = ++_activeRequestId;

    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(() async {
      await repo.refreshAllData();
      return _fetchDataForStation(repo, targetDeviceId, requestId);
    });

    if (requestId == _activeRequestId &&
        ref.read(selectedDeviceIdProvider) == targetDeviceId) {
      state = next;
    }
  }

  /// Chuyển đổi sang trạm quan trắc khác theo station ID thật (tương thích fallback tên hiển thị)
  Future<void> changeStation(String stationIdOrName) async {
    final newDeviceId = ApiConstants.resolveDeviceIdFromStationName(stationIdOrName);
    if (ref.read(selectedDeviceIdProvider) == newDeviceId && state.hasValue) {
      return;
    }
    ref.read(selectedDeviceIdProvider.notifier).state = newDeviceId;
  }
}

final weatherDashboardProvider =
    AsyncNotifierProvider<WeatherDashboardNotifier, WeatherDashboardState>(() {
  return WeatherDashboardNotifier();
});
