import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_monitoring/core/utils/weather_unit_helper.dart';
import 'package:weather_monitoring/data/mock/mock_weather_data.dart';
import 'package:weather_monitoring/main.dart';
import 'package:weather_monitoring/views/screens/history_7d_screen.dart';
import 'package:weather_monitoring/views/screens/intra_day_detail_screen.dart';

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

    testWidgets('History7dScreen renders "Lịch sử các ngày" and concise temperature metric', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: History7dScreen(),
          ),
        ),
      );

      // Wait for mock delay
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify section header
      expect(find.text('Lịch sử các ngày'), findsOneWidget);
      expect(find.text('Chi tiết tổng hợp từng ngày'), findsNothing);
      expect(find.text('Nhiệt độ TB'), findsWidgets);
    });

    testWidgets('IntraDayDetailScreen renders interval chips and "Bản ghi gần nhất"', (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: IntraDayDetailScreen(),
          ),
        ),
      );

      // Wait for mock delay
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify interval chips exist (15 phút, 30 phút, 1 tiếng; không có 5 phút hay chữ bước đo)
      expect(find.text('15 phút'), findsOneWidget);
      expect(find.text('30 phút'), findsOneWidget);
      expect(find.text('1 tiếng'), findsOneWidget);
      expect(find.text('5 phút'), findsNothing);
      expect(find.text('Bước đo:'), findsNothing);

      // Verify section header
      expect(find.text('Bản ghi gần nhất'), findsOneWidget);
      expect(find.text('Bản ghi đo gần nhất'), findsNothing);
    });
  });
}
