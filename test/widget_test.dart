import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_monitoring/core/utils/weather_unit_helper.dart';
import 'package:weather_monitoring/data/mock/mock_weather_data.dart';
import 'package:weather_monitoring/main.dart';

void main() {
  group('MockWeatherDataGenerator Tests', () {
    test('generateIntraDay5m produces valid points from 00:00 to now', () {
      final points = MockWeatherDataGenerator.generateIntraDay5m();
      expect(points, isNotEmpty);
      expect(points.first.minutesFromMidnight, equals(0)); // Start at 00:00
      expect(points.last.minutesFromMidnight, greaterThanOrEqualTo(0));
      for (final p in points) {
        expect(p.temperature, inInclusiveRange(10.0, 45.0));
        expect(p.humidity, inInclusiveRange(0.0, 100.0));
        expect(p.windSpeed, greaterThanOrEqualTo(0.0));
        expect(p.rainfall, greaterThanOrEqualTo(0.0));
      }
    });

    test('generate7DaysSummary generates exactly 7 items', () {
      final summaries = MockWeatherDataGenerator.generate7DaysSummary();
      expect(summaries.length, equals(7));
      expect(summaries.last.dayOfWeek, equals('Hôm nay'));
    });

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
        const ProviderScope(
          child: WeatherMonitoringApp(),
        ),
      );

      // Wait for mock delay and shimmer
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify Dashboard and AppHeaderBar actions exist
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.text('Thời tiết hôm nay'), findsOneWidget);
      expect(find.text('Lịch sử'), findsOneWidget);
    });
  });
}
