import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_monitoring/core/utils/weather_unit_helper.dart';
import 'package:weather_monitoring/data/models/weather_current_model.dart';
import 'package:weather_monitoring/data/models/weather_daily_summary.dart';
import 'package:weather_monitoring/data/models/weather_point.dart';
import 'package:weather_monitoring/data/repositories/weather_repository.dart';
import 'package:weather_monitoring/main.dart';
import 'package:weather_monitoring/providers/weather_dashboard_provider.dart';
import 'package:weather_monitoring/views/screens/history_7d_screen.dart';
import 'package:weather_monitoring/views/screens/intra_day_detail_screen.dart';

/// Fake repository dùng riêng cho việc cô lập môi trường Widget Tests
class _TestStubWeatherRepository implements WeatherRepository {
  @override
  Future<WeatherCurrentModel> getCurrentWeather() async {
    return WeatherCurrentModel(
      stationId: 'adht_weather_01',
      stationName: 'Trạm IoT 01 - Trung Tâm',
      timestamp: DateTime.now(),
      temperature: 28.5,
      humidity: 70.0,
      rainfall: 0.0,
      windSpeed: 10.0,
      isOnline: true,
    );
  }

  @override
  Future<List<WeatherPoint>> getIntraDayData() async {
    final now = DateTime.now();
    return List.generate(12, (index) {
      return WeatherPoint(
        timestamp: now.subtract(Duration(minutes: (11 - index) * 5)),
        temperature: 28.0 + (index * 0.1),
        humidity: 65.0,
        rainfall: 0.0,
        windSpeed: 8.0,
      );
    });
  }

  @override
  Future<List<WeatherDailySummary>> get7DaysSummary() async {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final date = now.subtract(Duration(days: 6 - i));
      return WeatherDailySummary(
        date: date,
        dayOfWeek: '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}',
        avgTemperature: 28.0 + (i * 0.2),
        minTemperature: 25.0,
        maxTemperature: 31.0,
        avgHumidity: 70.0,
        totalRainfall: 0.0,
        avgWindSpeed: 10.0,
        hasData: true,
      );
    });
  }

  @override
  Future<void> refreshAllData() async {}
}

void main() {
  group('WeatherUnitHelper Tests', () {
    test('WeatherUnitHelper qualitative assessments return valid strings', () {
      expect(WeatherUnitHelper.getTemperatureAssessment(28.0), contains('Ấm áp'));
      expect(WeatherUnitHelper.getHumidityAssessment(65.0), equals('Dễ chịu'));
      expect(WeatherUnitHelper.getRainfallAssessment(0.0), equals('Không mưa'));
      expect(WeatherUnitHelper.getWindAssessment(12.0), equals('Cấp 3'));
    });
  });

  group('Widget Navigation & Render Tests', () {
    testWidgets('App renders correctly with dashboard and header actions', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weatherRepositoryProvider.overrideWithValue(_TestStubWeatherRepository()),
          ],
          child: const WeatherMonitoringApp(),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Dashboard and AppHeaderBar actions exist
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.text('Thời tiết hôm nay'), findsOneWidget);
      expect(find.text('Lịch sử'), findsOneWidget);
    });

    testWidgets('History7dScreen renders "Lịch sử các ngày" and concise temperature metric', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weatherRepositoryProvider.overrideWithValue(_TestStubWeatherRepository()),
          ],
          child: const MaterialApp(
            home: History7dScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify section header
      expect(find.text('Lịch sử các ngày'), findsOneWidget);
      expect(find.text('Chi tiết tổng hợp từng ngày'), findsNothing);
      expect(find.text('Nhiệt độ TB'), findsWidgets);
    });

    testWidgets('IntraDayDetailScreen renders metric chips, chart and "Bản ghi gần nhất" without interval chips', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            weatherRepositoryProvider.overrideWithValue(_TestStubWeatherRepository()),
          ],
          child: const MaterialApp(
            home: IntraDayDetailScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify interval chips are removed completely
      expect(find.text('15 phút'), findsNothing);
      expect(find.text('30 phút'), findsNothing);
      expect(find.text('1 tiếng'), findsNothing);
      expect(find.text('5 phút'), findsNothing);
      expect(find.text('Bước đo:'), findsNothing);

      // Verify metric chips exist
      expect(find.text('Nhiệt độ'), findsOneWidget);
      expect(find.text('Độ ẩm'), findsOneWidget);

      // Verify section header
      expect(find.text('Bản ghi gần nhất'), findsOneWidget);
      expect(find.text('Bản ghi đo gần nhất'), findsNothing);
    });
  });
}
