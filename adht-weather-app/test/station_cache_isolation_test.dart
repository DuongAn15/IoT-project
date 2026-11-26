import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_monitoring/core/constants/api_constants.dart';
import 'package:weather_monitoring/data/models/weather_current_model.dart';
import 'package:weather_monitoring/data/models/weather_monitoring_record.dart';
import 'package:weather_monitoring/data/repositories/app_weather_repository.dart';
import 'package:weather_monitoring/data/storage/latest_weather_file_storage.dart';

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
      ApiConstants.resolveDeviceIdFromStationName('Trạm IoT 02 - Bán Đảo Sơn Trà'),
      'adht_weather_02',
    );
    expect(
      ApiConstants.resolveDeviceIdFromStationName('adht_weather_03'),
      'adht_weather_03',
    );
  });

  test('buildContinuous7DaysSummary uses rainfallMm instead of summing rain_rate', () {
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
  });
}
