import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:weather_monitoring/core/constants/api_constants.dart';
import 'package:weather_monitoring/data/database/app_database.dart';
import 'package:weather_monitoring/data/database/weather_monitoring_dao.dart';
import 'package:weather_monitoring/data/models/weather_monitoring_record.dart';
import 'package:weather_monitoring/data/models/weather_point_5m.dart';
import 'package:weather_monitoring/data/repositories/app_weather_repository.dart';

void main() {
  // Khởi tạo SQLite FFI cho môi trường test trên Desktop/CLI
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('WeatherMonitoringRecord Model Tests', () {
    test('toMap and fromMap should serialize and deserialize correctly', () {
      final now = DateTime.now();
      final record = WeatherMonitoringRecord(
        id: 1,
        deviceId: 'adht_weather_01',
        temperature: 28.5,
        humidity: 75.0,
        rainfall: 12.4,
        windSpeed: 18.2,
        recordedAt: now,
      );

      final map = record.toMap();
      expect(map['device_id'], 'adht_weather_01');
      expect(map['temperature'], 28.5);
      expect(map['humidity'], 75.0);
      expect(map['rainfall'], 12.4);
      expect(map['wind_speed'], 18.2);
      expect(map['timestamp'], now.millisecondsSinceEpoch);

      final fromMapRecord = WeatherMonitoringRecord.fromMap(map);
      expect(fromMapRecord.deviceId, record.deviceId);
      expect(fromMapRecord.temperature, record.temperature);
      expect(fromMapRecord.humidity, record.humidity);
      expect(fromMapRecord.rainfall, record.rainfall);
      expect(fromMapRecord.windSpeed, record.windSpeed);
      expect(fromMapRecord.recordedAt.hour, record.recordedAt.hour);
      expect(fromMapRecord.recordedAt.minute, record.recordedAt.minute);
    });

    test('Multiple toMap and fromMap roundtrips should not drift or add hours', () {
      final initial = WeatherMonitoringRecord.fromJson({
        'device_id': 'adht_weather_01',
        'temp': 24.5,
        'humi': 55.0,
        'rain_rate': 0.0,
        'wind_speed': 1.2,
        'recorded_at': '2026-11-11T10:00:00.000Z', // 17:00 GMT+7
      });

      expect(initial.recordedAt.hour, equals(17));

      // Roundtrip 1
      final map1 = initial.toMap();
      final round1 = WeatherMonitoringRecord.fromMap(map1);
      expect(round1.recordedAt.hour, equals(17));
      expect(round1.recordedAt.day, equals(11));

      // Roundtrip 2
      final map2 = round1.toMap();
      final round2 = WeatherMonitoringRecord.fromMap(map2);
      expect(round2.recordedAt.hour, equals(17));
      expect(round2.recordedAt.day, equals(11));
    });

    test('fromJson should parse backend API item correctly and convert UTC to GMT+7', () {
      final json = {
        'device_id': 'adht_weather_01',
        'temp': 26.3,
        'humi': 80.5,
        'rain_rate': 2.5,
        'wind_speed': 5.4,
        'recorded_at': '2026-11-10T12:00:00.000Z',
      };

      final record = WeatherMonitoringRecord.fromJson(json);
      expect(record.deviceId, 'adht_weather_01');
      expect(record.temperature, 26.3);
      expect(record.humidity, 80.5);
      expect(record.rainfall, 2.5);
      expect(record.windSpeed, 5.4);
      // 12:00 UTC + 7 tiếng = 19:00 GMT+7 (giờ Việt Nam)
      expect(record.recordedAt.hour, equals(19));
      expect(record.recordedAt.minute, equals(0));
    });

    test('parseUtcToGmt7 handles day rollover correctly (e.g. 19:00 UTC to 02:00 next day GMT+7)', () {
      // 19:00 UTC ngày 10/11 -> cộng 7 tiếng = 02:00 ngày 11/11 GMT+7
      final json = {
        'device_id': 'adht_weather_01',
        'temp': 24.0,
        'humi': 75.0,
        'rain_rate': 0.0,
        'wind_speed': 2.0,
        'recorded_at': '2026-11-10T19:00:00.000Z',
      };

      final record = WeatherMonitoringRecord.fromJson(json);
      expect(record.recordedAt.day, equals(11));
      expect(record.recordedAt.hour, equals(2));
      expect(record.toWeatherPoint5m().minutesFromMidnight, equals(2 * 60));
    });

    test('toWeatherPoint5m converts record for chart consumption', () {
      final now = DateTime.now();
      final record = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 25.0,
        humidity: 70.0,
        rainfall: 0.0,
        windSpeed: 10.0,
        recordedAt: now,
      );

      final point = record.toWeatherPoint5m();
      expect(point.temperature, 25.0);
      expect(point.humidity, 70.0);
      expect(point.rainfall, 0.0);
      expect(point.windSpeed, 10.0);
      expect(point.timestamp, now);
    });
  });

  group('WeatherMonitoringDao SQLite Tests', () {
    late Database db;
    late AppDatabase appDatabase;
    late WeatherMonitoringDao dao;

    setUp(() async {
      // Sử dụng in-memory database độc lập cho từng ca test
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: ApiConstants.databaseVersion,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS ${ApiConstants.tableWeatherMonitoring} (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                device_id TEXT NOT NULL,
                temperature REAL NOT NULL,
                humidity REAL NOT NULL,
                rainfall REAL NOT NULL,
                wind_speed REAL NOT NULL,
                recorded_at TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                UNIQUE(device_id, recorded_at) ON CONFLICT REPLACE
              );
            ''');

            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_weather_monitoring_device_time 
              ON ${ApiConstants.tableWeatherMonitoring} (device_id, timestamp);
            ''');
          },
        ),
      );

      appDatabase = AppDatabase.withDatabase(db);
      dao = WeatherMonitoringDao(appDatabase);
    });

    tearDown(() async {
      await db.close();
    });

    test('insertRecord and count should work as expected', () async {
      final now = DateTime.now();
      final record = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 29.1,
        humidity: 68.0,
        rainfall: 0.0,
        windSpeed: 14.2,
        recordedAt: now,
      );

      final id = await dao.insertRecord(record);
      expect(id, greaterThan(0));

      final count = await dao.count(deviceId: 'adht_weather_01');
      expect(count, equals(1));

      final latest = await dao.getLatestRecord(deviceId: 'adht_weather_01');
      expect(latest, isNotNull);
      expect(latest!.temperature, equals(29.1));
      expect(latest.humidity, equals(68.0));
    });

    test('insertBatch inserts multiple records efficiently', () async {
      final now = DateTime.now();
      final records = List.generate(5, (index) {
        final time = now.subtract(Duration(hours: index));
        return WeatherMonitoringRecord(
          deviceId: 'adht_weather_01',
          temperature: 25.0 + index,
          humidity: 60.0 + index,
          rainfall: index.toDouble(),
          windSpeed: 10.0 + index,
          recordedAt: time,
        );
      });

      await dao.insertBatch(records);
      final count = await dao.count(deviceId: 'adht_weather_01');
      expect(count, equals(5));
    });

    test('UNIQUE constraint on (device_id, recorded_at) replaces existing record', () async {
      final time = DateTime(2026, 11, 11, 10, 0, 0);
      final record1 = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 25.0,
        humidity: 60.0,
        rainfall: 0.0,
        windSpeed: 10.0,
        recordedAt: time,
      );

      await dao.insertRecord(record1);

      // Cập nhật với cùng deviceId và recordedAt nhưng giá trị nhiệt độ mới
      final record2 = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 30.5,
        humidity: 65.0,
        rainfall: 5.0,
        windSpeed: 12.0,
        recordedAt: time,
      );

      await dao.insertRecord(record2);

      final count = await dao.count(deviceId: 'adht_weather_01');
      expect(count, equals(1)); // Không bị nhân đôi

      final latest = await dao.getLatestRecord(deviceId: 'adht_weather_01');
      expect(latest!.temperature, equals(30.5));
    });

    test('autoDeleteOlderThan7Days deletes records older than 7 days and retains recent ones', () async {
      final now = DateTime.now();

      // Bản ghi trong phạm vi 7 ngày
      final recentRecord1 = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 28.0,
        humidity: 70.0,
        rainfall: 0.0,
        windSpeed: 15.0,
        recordedAt: now.subtract(const Duration(hours: 2)), // 2 giờ trước
      );

      final recentRecord2 = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 27.0,
        humidity: 72.0,
        rainfall: 1.0,
        windSpeed: 14.0,
        recordedAt: now.subtract(const Duration(days: 3)), // 3 ngày trước
      );

      final recentRecord3 = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 26.0,
        humidity: 75.0,
        rainfall: 2.0,
        windSpeed: 12.0,
        recordedAt: now.subtract(const Duration(days: 6)), // 6 ngày trước
      );

      // Bản ghi quá 7 ngày
      final oldRecord1 = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 24.0,
        humidity: 80.0,
        rainfall: 5.0,
        windSpeed: 8.0,
        recordedAt: now.subtract(const Duration(days: 8)), // 8 ngày trước (quá 7 ngày)
      );

      final oldRecord2 = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 23.0,
        humidity: 85.0,
        rainfall: 10.0,
        windSpeed: 6.0,
        recordedAt: now.subtract(const Duration(days: 15)), // 15 ngày trước
      );

      // Chèn tất cả 5 bản ghi
      await dao.insertBatch([
        recentRecord1,
        recentRecord2,
        recentRecord3,
        oldRecord1,
        oldRecord2,
      ]);

      expect(await dao.count(), equals(5));

      // Thực thi cơ chế tự động xóa bản ghi quá 7 ngày
      final deletedCount = await dao.autoDeleteOlderThan7Days();
      expect(deletedCount, equals(2)); // Đã xóa đúng 2 bản ghi cũ

      // Tổng số bản ghi còn lại phải là 3
      expect(await dao.count(), equals(3));

      // Lấy danh sách 7 ngày
      final history7Days = await dao.getHistory7Days(deviceId: 'adht_weather_01');
      expect(history7Days.length, equals(3));
      // Các bản ghi còn lại đều phải có mốc thời gian trong vòng 7 ngày
      for (final r in history7Days) {
        expect(
          r.recordedAt.isAfter(now.subtract(const Duration(days: 7, hours: 1))),
          isTrue,
        );
      }
    });

    test('saveHistoryAndCleanup inserts new records and purges old ones in one operation', () async {
      final now = DateTime.now();

      // Đưa sẵn 1 bản ghi cũ 10 ngày trước
      await dao.insertRecord(
        WeatherMonitoringRecord(
          deviceId: 'adht_weather_01',
          temperature: 20.0,
          humidity: 90.0,
          rainfall: 20.0,
          windSpeed: 5.0,
          recordedAt: now.subtract(const Duration(days: 10)),
        ),
      );

      expect(await dao.count(), equals(1));

      // Batch mới với 2 bản ghi gần đây
      final newRecords = [
        WeatherMonitoringRecord(
          deviceId: 'adht_weather_01',
          temperature: 29.0,
          humidity: 65.0,
          rainfall: 0.0,
          windSpeed: 10.0,
          recordedAt: now.subtract(const Duration(hours: 1)),
        ),
        WeatherMonitoringRecord(
          deviceId: 'adht_weather_01',
          temperature: 30.0,
          humidity: 60.0,
          rainfall: 0.0,
          windSpeed: 12.0,
          recordedAt: now,
        ),
      ];

      await dao.saveHistoryAndCleanup(newRecords);

      // Bản ghi cũ 10 ngày đã bị xóa, còn lại 2 bản ghi mới
      expect(await dao.count(), equals(2));
      final history = await dao.getHistory7Days(deviceId: 'adht_weather_01');
      expect(history.length, equals(2));
    });
  });

  group('Continuous 7 Days Aggregation Tests', () {
    test('buildContinuous7DaysSummary returns exactly 7 items with dd/MM format and None for missing days', () {
      // Dữ liệu thực tế 8 bản ghi từ server
      final rawData = [
        {"device_id":"adht_weather_01","temp":31.18076923076923,"humi":65.36923076923077,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-05T10:46:05.976Z"},
        {"device_id":"adht_weather_01","temp":30.933898305084785,"humi":68.13898305084746,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-05T12:46:05.976Z"},
        {"device_id":"adht_weather_01","temp":31.887927565392182,"humi":68.93058350100632,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-05T13:46:05.976Z"},
        {"device_id":"adht_weather_01","temp":32.09576271186446,"humi":68.80127118644059,"rain_rate":0,"wind_speed":0.0007062146892655367,"recorded_at":"2026-11-05T14:46:05.976Z"},
        {"device_id":"adht_weather_01","temp":32.40000000000005,"humi":69,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-05T15:46:05.976Z"},
        {"device_id":"adht_weather_01","temp":23.83125000000005,"humi":60.847058823529494,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-10T14:46:05.976Z"},
        {"device_id":"adht_weather_01","temp":23.83612903225807,"humi":61.59612903225808,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-10T15:46:05.976Z"},
        {"device_id":"adht_weather_01","temp":23.22727272727274,"humi":51.07474747474743,"rain_rate":0,"wind_speed":0.00202020202020202,"recorded_at":"2026-11-11T05:46:05.976Z"}
      ];

      final records = rawData
          .map((item) => WeatherMonitoringRecord.fromJson(item))
          .toList();

      final summaries = AppWeatherRepository.buildContinuous7DaysSummary(
        records,
        referenceDate: DateTime(2026, 11, 11),
      );

      // Phải có đúng 7 ngày
      expect(summaries.length, equals(7));

      // Ngày 05/11: Có dữ liệu (5 bản ghi)
      expect(summaries[0].dayOfWeek, equals('05/11'));
      expect(summaries[0].hasData, isTrue);
      expect(summaries[0].avgTemperature, closeTo(31.7, 0.1));

      // Các ngày 06/11, 07/11, 08/11, 09/11: Không có dữ liệu (None)
      expect(summaries[1].dayOfWeek, equals('06/11'));
      expect(summaries[1].hasData, isFalse);

      expect(summaries[2].dayOfWeek, equals('07/11'));
      expect(summaries[2].hasData, isFalse);

      expect(summaries[3].dayOfWeek, equals('08/11'));
      expect(summaries[3].hasData, isFalse);

      expect(summaries[4].dayOfWeek, equals('09/11'));
      expect(summaries[4].hasData, isFalse);

      // Ngày 10/11: Có dữ liệu (2 bản ghi)
      expect(summaries[5].dayOfWeek, equals('10/11'));
      expect(summaries[5].hasData, isTrue);
      expect(summaries[5].avgTemperature, closeTo(23.8, 0.1));

      // Ngày 11/11: Có dữ liệu (1 bản ghi)
      expect(summaries[6].dayOfWeek, equals('11/11'));
      expect(summaries[6].hasData, isTrue);
      expect(summaries[6].avgTemperature, closeTo(23.2, 0.1));
    });

    test('Intra-day points filter keeps only records from 00:00 today and excludes yesterday records', () {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);

      final yesterdayRecord1 = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 25.0,
        humidity: 70.0,
        rainfall: 0.0,
        windSpeed: 2.0,
        recordedAt: todayStart.subtract(const Duration(hours: 4)), // 20h hôm qua
      );

      final yesterdayRecord2 = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 24.0,
        humidity: 72.0,
        rainfall: 0.0,
        windSpeed: 1.5,
        recordedAt: todayStart.subtract(const Duration(minutes: 30)), // 23h30 hôm qua
      );

      final todayRecord1 = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 26.0,
        humidity: 68.0,
        rainfall: 0.0,
        windSpeed: 3.0,
        recordedAt: todayStart.add(const Duration(hours: 2)), // 02h00 hôm nay
      );

      final todayRecord2 = WeatherMonitoringRecord(
        deviceId: 'adht_weather_01',
        temperature: 29.0,
        humidity: 60.0,
        rainfall: 0.0,
        windSpeed: 4.0,
        recordedAt: todayStart.add(const Duration(hours: 10)), // 10h00 hôm nay
      );

      final allRecords = [
        yesterdayRecord1,
        yesterdayRecord2,
        todayRecord1,
        todayRecord2,
      ];

      // Lọc theo ngày hôm nay chuẩn hóa
      final todayOnly = allRecords.where((r) {
        final d = r.recordedAt;
        return d.year == todayStart.year &&
               d.month == todayStart.month &&
               d.day == todayStart.day;
      }).toList();

      expect(todayOnly.length, equals(2));
      expect(todayOnly.first.recordedAt.hour, equals(2));
      expect(todayOnly.last.recordedAt.hour, equals(10));
    });

    test('Real backend 14 records filters only today 9 records and ignores yesterday 5 records', () {
      final rawBackendData = [
        {"device_id":"adht_weather_01","temp":18.14,"humi":47.12,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-10T15:13:32.048Z"},
        {"device_id":"adht_weather_01","temp":23.86,"humi":61.29,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-10T15:23:32.048Z"},
        {"device_id":"adht_weather_01","temp":24.01,"humi":61.01,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-10T15:33:32.048Z"},
        {"device_id":"adht_weather_01","temp":24.38,"humi":61.71,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-10T15:43:32.048Z"},
        {"device_id":"adht_weather_01","temp":23.07,"humi":61.40,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-10T16:13:32.048Z"},
        {"device_id":"adht_weather_01","temp":23.04,"humi":50.96,"rain_rate":0,"wind_speed":0.003,"recorded_at":"2026-11-11T05:43:32.048Z"},
        {"device_id":"adht_weather_01","temp":23.46,"humi":51.21,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-11T05:53:32.048Z"},
        {"device_id":"adht_weather_01","temp":21.74,"humi":47.01,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-11T09:53:32.048Z"},
        {"device_id":"adht_weather_01","temp":24.09,"humi":49.35,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-11T10:03:32.048Z"},
        {"device_id":"adht_weather_01","temp":24.41,"humi":49.21,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-11T10:13:32.048Z"},
        {"device_id":"adht_weather_01","temp":24.43,"humi":49.07,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-11T10:23:32.048Z"},
        {"device_id":"adht_weather_01","temp":24.42,"humi":48.81,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-11T10:33:32.048Z"},
        {"device_id":"adht_weather_01","temp":24.41,"humi":48.21,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-11T10:43:32.048Z"},
        {"device_id":"adht_weather_01","temp":24.41,"humi":48.46,"rain_rate":0,"wind_speed":0,"recorded_at":"2026-11-11T10:53:32.048Z"}
      ];

      final records = rawBackendData.map((e) => WeatherMonitoringRecord.fromJson(e)).toList();
      final today = DateTime(2026, 11, 11);

      final todayRecords = records.where((r) {
        final d = r.recordedAt;
        return d.year == today.year && d.month == today.month && d.day == today.day;
      }).toList();

      expect(todayRecords.length, equals(9));
      expect(todayRecords.first.recordedAt.hour, equals(12));
      expect(todayRecords.first.recordedAt.minute, equals(43));
      expect(todayRecords.last.recordedAt.hour, equals(17));
      expect(todayRecords.last.recordedAt.minute, equals(53));

      // Test interval sampling
      final points = todayRecords.map((r) => r.toWeatherPoint5m()).toList();
      final sampled15m = WeatherPoint5m.sampleByInterval(points, 15);
      expect(sampled15m.isNotEmpty, isTrue);
      expect(sampled15m.last.minutesFromMidnight, points.last.minutesFromMidnight);
    });
  });
}
