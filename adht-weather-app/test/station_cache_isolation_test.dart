import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_monitoring/core/constants/api_constants.dart';
import 'package:weather_monitoring/data/models/station_info.dart';
import 'package:weather_monitoring/data/models/weather_current_model.dart';
import 'package:weather_monitoring/data/models/weather_daily_summary.dart';
import 'package:weather_monitoring/data/models/weather_monitoring_record.dart';
import 'package:weather_monitoring/data/models/weather_point.dart';
import 'package:weather_monitoring/data/repositories/app_weather_repository.dart';
import 'package:weather_monitoring/data/repositories/weather_repository.dart';
import 'package:weather_monitoring/data/storage/latest_weather_file_storage.dart';
import 'package:weather_monitoring/data/storage/station_catalogue_storage.dart';
import 'package:weather_monitoring/providers/device_settings_provider.dart';
import 'package:weather_monitoring/providers/weather_dashboard_provider.dart';

class _DelayedFakeRepo implements WeatherRepository {
  final String stationId;
  final Future<WeatherCurrentModel> Function() fetchCurrent;

  _DelayedFakeRepo(this.stationId, this.fetchCurrent);

  @override
  Future<WeatherCurrentModel> getCurrentWeather() => fetchCurrent();

  @override
  Future<List<WeatherPoint>> getIntraDayData() async => [];

  @override
  Future<List<WeatherDailySummary>> get7DaysSummary() async => [];

  @override
  Future<void> refreshAllData() async {}
}

void main() {
  test('LatestWeatherFileStorage isolates cache per stationId', () async {
    final tempDir = await Directory.systemTemp.createTemp('adht_cache_test_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final storage = LatestWeatherFileStorage(customDirectoryPath: tempDir.path);
    final station1 = WeatherCurrentModel(
      stationId: 'adht_weather_01',
      stationName: 'Trạm 01',
      timestamp: DateTime(2026, 11, 26, 12, 0),
      temperature: 30.0,
      humidity: 70.0,
      rainfall: 0.0,
      windSpeed: 2.0,
      isOnline: true,
    );
    final station2 = WeatherCurrentModel(
      stationId: 'adht_weather_02',
      stationName: 'Trạm 02',
      timestamp: DateTime(2026, 11, 26, 12, 5),
      temperature: 24.5,
      humidity: 82.0,
      rainfall: 5.0,
      windSpeed: 4.5,
      isOnline: true,
    );

    await storage.saveLatest(station1);
    await storage.saveLatest(station2);

    final loaded1 = await storage.readLatest(deviceId: 'adht_weather_01');
    final loaded2 = await storage.readLatest(deviceId: 'adht_weather_02');
    final loaded3 = await storage.readLatest(deviceId: 'adht_weather_03');

    expect(loaded1?.stationId, 'adht_weather_01');
    expect(loaded1?.temperature, 30.0);
    expect(loaded2?.stationId, 'adht_weather_02');
    expect(loaded2?.temperature, 24.5);
    expect(loaded3, isNull);
  });

  test('resolveDeviceIdFromStationName maps display names to device IDs', () {
    expect(
      ApiConstants.resolveDeviceIdFromStationName(
        'Trạm IoT 02 - Bán Đảo Sơn Trà',
      ),
      'adht_weather_02',
    );
    expect(
      ApiConstants.resolveDeviceIdFromStationName('adht_weather_03'),
      'adht_weather_03',
    );
  });

  test(
    'buildContinuous7DaysSummary uses rainfallMm instead of summing rain_rate',
    () {
      final now = DateTime(2026, 11, 26, 12, 0);
      final records = [
        WeatherMonitoringRecord.fromJson({
          'device_id': 'adht_weather_01',
          'temp': 28.0,
          'humi': 75.0,
          'rain_rate': 12.0,
          'rainfall_mm': 2.0,
          'wind_speed': 3.0,
          'recorded_at': '2026-11-26T04:00:00.000Z',
        }),
        WeatherMonitoringRecord.fromJson({
          'device_id': 'adht_weather_01',
          'temp': 29.0,
          'humi': 73.0,
          'rain_rate': 6.0,
          'rainfall_mm': 1.0,
          'wind_speed': 2.0,
          'recorded_at': '2026-11-26T05:00:00.000Z',
        }),
      ];

      final summaries = AppWeatherRepository.buildContinuous7DaysSummary(
        records,
        referenceDate: now,
      );
      expect(summaries.last.totalRainfall, 3.0);
    },
  );

  test('buildContinuous7DaysSummary never sums rain_rate when rainfallMm is null and tracks provenance', () {
    final now = DateTime(2026, 11, 26, 14, 0);
    final yesterday = DateTime(2026, 11, 25, 10, 0);

    final summaries = AppWeatherRepository.buildContinuous7DaysSummary([
      // Legacy record: rain_rate = 15.0 mm/h, rainfallMm = null
      WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 28.0,
        humidity: 70.0,
        rainfall: 15.0,
        windSpeed: 2.0,
        source: 'v1_legacy',
        rainQuality: 'estimated',
        recordedAt: yesterday,
      ),
      // V2 observed record with tempMin/tempMax
      WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 27.0,
        humidity: 75.0,
        rainfall: 3.0,
        rainfallMm: 0.8,
        windSpeed: 2.5,
        source: 'v2',
        rainQuality: 'observed',
        tempMin: 25.2,
        tempMax: 29.4,
        recordedAt: now,
      ),
    ], referenceDate: now);

    final yesterdaySummary = summaries[summaries.length - 2];
    expect(yesterdaySummary.hasData, isTrue);
    expect(yesterdaySummary.hasRainfallAmount, isFalse);
    expect(yesterdaySummary.rainQuality, 'unknown');
    expect(yesterdaySummary.totalRainfall, 0.0);

    final todaySummary = summaries.last;
    expect(todaySummary.hasRainfallAmount, isTrue);
    expect(todaySummary.rainQuality, 'observed');
    expect(todaySummary.totalRainfall, 0.8);
    expect(todaySummary.minTemperature, 25.2);
    expect(todaySummary.maxTemperature, 29.4);
  });

  test(
    'local-day grouping uses the mobile clock and preserves UTC instants',
    () {
      expect(
        AppWeatherRepository.computeOverlapSince(
          '2026-11-27T10:00:00.000Z',
          const Duration(hours: 1),
        ),
        '2026-11-27T09:00:00.000Z',
      );
      final local = DateTime(2026, 11, 27, 0, 30);
      final instant = local.toUtc();
      final summaries = AppWeatherRepository.buildContinuous7DaysSummary([
        WeatherMonitoringRecord(
          deviceId: 'adht_weather_01',
          temperature: 26,
          humidity: 70,
          rainfall: 0,
          rainfallMm: 0.4,
          windSpeed: 1.5,
          rainQuality: 'observed',
          recordedAt: instant,
        ),
      ], referenceDate: DateTime(2026, 11, 27, 12));
      expect(summaries.last.hasData, isTrue);
      expect(summaries.last.totalRainfall, 0.4);
      expect(instant.toLocal().day, 27);
    },
  );

  test('cutover provenance and partial coverage reach the daily summary', () {
    final now = DateTime(2026, 11, 27, 12);
    final summaries = AppWeatherRepository.buildContinuous7DaysSummary([
      WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 30,
        humidity: 60,
        rainfall: 0,
        rainfallMm: 0.3,
        windSpeed: 2,
        source: 'v2_cutover',
        isPartial: true,
        recordedAt: now,
      ),
    ], referenceDate: now);
    expect(summaries.last.isCutoverDay, isTrue);
    expect(summaries.last.isPartial, isTrue);
    expect(summaries.last.totalRainfall, 0.3);
    expect(summaries[summaries.length - 2].isCutoverDay, isFalse);
  });

  test(
    'StationCatalogueStorage persists and restores station list offline',
    () async {
      final tempDir = await Directory.systemTemp.createTemp('adht_cat_test_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final storage = StationCatalogueStorage(
        customDirectoryPath: tempDir.path,
      );
      await storage.saveCatalogue(const [
        StationInfo(
          deviceId: 'adht_weather_01',
          name: 'Station 01',
          mac: 'AA:BB:CC:DD:EE:01',
          location: 'Đà Nẵng, Việt Nam',
        ),
        StationInfo(
          deviceId: 'adht_weather_02',
          name: 'Station 02',
          mac: 'AA:BB:CC:DD:EE:02',
        ),
      ]);

      final restored = await storage.readCatalogue();
      expect(restored.length, 2);
      expect(restored[1].deviceId, 'adht_weather_02');
      expect(restored[1].name, 'Station 02');
      expect(restored[0].location, 'Đà Nẵng, Việt Nam');
      expect(restored[1].location, 'Bán đảo Sơn Trà, Đà Nẵng, Việt Nam');
    },
  );

  test(
    'WeatherDashboardNotifier discards stale response when switching A -> B',
    () async {
      final stationACompleter = Completer<WeatherCurrentModel>();
      final container = ProviderContainer(
        overrides: [
          weatherRepositoryProvider.overrideWith((ref) {
            final id = ref.watch(selectedDeviceIdProvider);
            if (id == 'adht_weather_01') {
              return _DelayedFakeRepo(id, () => stationACompleter.future);
            }
            return _DelayedFakeRepo(
              id,
              () async => WeatherCurrentModel(
                stationId: 'adht_weather_02',
                stationName: 'Station 02',
                timestamp: DateTime(2026, 11, 26, 12, 0),
                temperature: 22.0,
                humidity: 80.0,
                rainfall: 1.0,
                windSpeed: 3.0,
                isOnline: false,
              ),
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      // Start loading A
      final sub = container.listen(weatherDashboardProvider, (_, _) {});
      addTearDown(sub.close);

      // Switch to B while A is still pending
      await container
          .read(weatherDashboardProvider.notifier)
          .changeStation('adht_weather_02');
      final stateB = await container.read(weatherDashboardProvider.future);
      expect(stateB.current.stationId, 'adht_weather_02');

      // Complete A late -> must NOT overwrite B
      stationACompleter.complete(
        WeatherCurrentModel(
          stationId: 'adht_weather_01',
          stationName: 'Station 01',
          timestamp: DateTime(2026, 11, 26, 12, 0),
          temperature: 35.0,
          humidity: 50.0,
          rainfall: 0.0,
          windSpeed: 1.0,
          isOnline: true,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        container.read(weatherDashboardProvider).valueOrNull?.current.stationId,
        'adht_weather_02',
      );
    },
  );

  test('WeatherDashboardNotifier.refresh() fetches once and keeps existing UI state visible', () async {
    int currentCalls = 0;
    int intradayCalls = 0;
    int weeklyCalls = 0;
    int refreshAllCalls = 0;
    Completer<WeatherCurrentModel>? refreshCompleter;

    final repo = _CountingFakeRepo(
      onCurrent: () {
        currentCalls++;
        if (refreshCompleter != null) return refreshCompleter.future;
        return Future.value(
          WeatherCurrentModel(
            stationId: 'adht_weather_01',
            stationName: 'Station 01',
            timestamp: DateTime(2026, 11, 26, 12, 0),
            temperature: 29.0,
            humidity: 70.0,
            rainfall: 0.0,
            windSpeed: 2.0,
            isOnline: true,
          ),
        );
      },
      onIntraday: () async {
        intradayCalls++;
        return [];
      },
      onWeekly: () async {
        weeklyCalls++;
        return [];
      },
      onRefreshAll: () async {
        refreshAllCalls++;
      },
    );

    final container = ProviderContainer(
      overrides: [weatherRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final sub = container.listen(weatherDashboardProvider, (_, _) {});
    addTearDown(sub.close);

    final initial = await container.read(weatherDashboardProvider.future);
    expect(initial.current.temperature, 29.0);
    expect(currentCalls, 1);
    expect(intradayCalls, 1);
    expect(weeklyCalls, 1);
    expect(refreshAllCalls, 0);

    refreshCompleter = Completer<WeatherCurrentModel>();
    final refreshFuture = container
        .read(weatherDashboardProvider.notifier)
        .refresh();

    // Existing data stays visible (not reset to AsyncLoading without value)
    final duringRefresh = container.read(weatherDashboardProvider);
    expect(duringRefresh.hasValue, isTrue);
    expect(duringRefresh.value?.current.temperature, 29.0);

    refreshCompleter.complete(
      WeatherCurrentModel(
        stationId: 'adht_weather_01',
        stationName: 'Station 01',
        timestamp: DateTime(2026, 11, 26, 12, 5),
        temperature: 30.5,
        humidity: 68.0,
        rainfall: 0.2,
        windSpeed: 2.5,
        isOnline: true,
      ),
    );
    await refreshFuture;

    expect(
      container.read(weatherDashboardProvider).value?.current.temperature,
      30.5,
    );
    expect(currentCalls, 2);
    expect(intradayCalls, 2);
    expect(weeklyCalls, 2);
    expect(refreshAllCalls, 0);
  });
}

class _CountingFakeRepo implements WeatherRepository {
  final Future<WeatherCurrentModel> Function() onCurrent;
  final Future<List<WeatherPoint>> Function() onIntraday;
  final Future<List<WeatherDailySummary>> Function() onWeekly;
  final Future<void> Function() onRefreshAll;

  _CountingFakeRepo({
    required this.onCurrent,
    required this.onIntraday,
    required this.onWeekly,
    required this.onRefreshAll,
  });

  @override
  Future<WeatherCurrentModel> getCurrentWeather() => onCurrent();

  @override
  Future<List<WeatherPoint>> getIntraDayData() => onIntraday();

  @override
  Future<List<WeatherDailySummary>> get7DaysSummary() => onWeekly();

  @override
  Future<void> refreshAllData() => onRefreshAll();
}
