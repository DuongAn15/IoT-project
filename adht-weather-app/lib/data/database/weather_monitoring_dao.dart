import 'package:sqflite/sqflite.dart';
import '../../core/constants/api_constants.dart';
import '../models/weather_monitoring_record.dart';
import 'app_database.dart';

/// DAO phụ trách truy vấn, lưu trữ và tự động dọn dẹp lịch sử thời tiết trong SQLite
/// Quản lý độc lập 2 bảng:
/// 1. `weather_inday`: Lưu chuỗi dữ liệu trong ngày (tự động xóa bản ghi quá 24h)
/// 2. `weather_week`: Lưu lịch sử 7 ngày gần nhất (tự động xóa bản ghi quá 7 ngày)
class WeatherMonitoringDao {
  final AppDatabase _appDatabase;

  WeatherMonitoringDao([AppDatabase? database])
      : _appDatabase = database ?? AppDatabase.instance;

  String get tableInday => ApiConstants.tableWeatherInday;
  String get tableWeek => ApiConstants.tableWeatherWeek;

  // =========================================================================
  // 1. CÁC THAO TÁC TRÊN BẢNG weather_inday (Dữ liệu trong ngày / 24h)
  // =========================================================================

  /// Thêm hoặc ghi đè một bản ghi vào bảng weather_inday
  Future<int> insertIndayRecord(WeatherMonitoringRecord record) async {
    final db = await _appDatabase.database;
    return await db.insert(
      tableInday,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Thêm danh sách bản ghi 24h vào bảng weather_inday theo Batch Transaction
  Future<void> insertIndayBatch(List<WeatherMonitoringRecord> records) async {
    if (records.isEmpty) return;

    final db = await _appDatabase.database;
    final batch = db.batch();

    for (final record in records) {
      batch.insert(
        tableInday,
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Lấy toàn bộ bản ghi trong ngày từ bảng weather_inday
  Future<List<WeatherMonitoringRecord>> getIndayRecords({
    String deviceId = ApiConstants.defaultStationId,
  }) async {
    final db = await _appDatabase.database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableInday,
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => WeatherMonitoringRecord.fromMap(map)).toList();
  }

  /// Tự động xóa bản ghi cũ hơn 24 giờ trong bảng weather_inday
  Future<int> autoDeleteIndayOlderThan24Hours() async {
    final db = await _appDatabase.database;
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: ApiConstants.cacheRetentionHoursInday))
        .millisecondsSinceEpoch;

    return await db.delete(
      tableInday,
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  /// Xóa các bản ghi tương lai sai lệch trong bảng weather_inday
  Future<int> purgeFutureIndayRecords() async {
    final db = await _appDatabase.database;
    final nowEpoch = DateTime.now().millisecondsSinceEpoch;
    return await db.delete(
      tableInday,
      where: 'timestamp > ?',
      whereArgs: [nowEpoch + 600000],
    );
  }

  /// Đồng bộ lưu danh sách bản ghi trong ngày và tự động dọn dẹp dữ liệu quá 24h
  Future<void> saveIndayHistoryAndCleanup(
    List<WeatherMonitoringRecord> records,
  ) async {
    if (records.isNotEmpty) {
      await insertIndayBatch(records);
    }
    await autoDeleteIndayOlderThan24Hours();
    await purgeFutureIndayRecords();
  }

  /// Đếm tổng số bản ghi hiện có trong bảng weather_inday
  Future<int> countInday({String? deviceId}) async {
    final db = await _appDatabase.database;
    final result = await db.rawQuery(
      deviceId != null
          ? 'SELECT COUNT(*) as total FROM $tableInday WHERE device_id = ?'
          : 'SELECT COUNT(*) as total FROM $tableInday',
      deviceId != null ? [deviceId] : null,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  // =========================================================================
  // 2. CÁC THAO TÁC TRÊN BẢNG weather_week (Lịch sử 7 ngày)
  // =========================================================================

  /// Thêm hoặc ghi đè một bản ghi vào bảng weather_week
  Future<int> insertWeekRecord(WeatherMonitoringRecord record) async {
    final db = await _appDatabase.database;
    return await db.insert(
      tableWeek,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Thêm danh sách bản ghi 7 ngày vào bảng weather_week theo Batch Transaction
  Future<void> insertWeekBatch(List<WeatherMonitoringRecord> records) async {
    if (records.isEmpty) return;

    final db = await _appDatabase.database;
    final batch = db.batch();

    for (final record in records) {
      batch.insert(
        tableWeek,
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Lấy danh sách bản ghi lịch sử trong vòng 7 ngày gần nhất của trạm từ weather_week
  Future<List<WeatherMonitoringRecord>> getWeekHistory7Days({
    String deviceId = ApiConstants.defaultStationId,
  }) async {
    final db = await _appDatabase.database;
    final cutoffTimestamp = DateTime.now()
        .subtract(const Duration(days: ApiConstants.cacheRetentionDays))
        .millisecondsSinceEpoch;

    final List<Map<String, dynamic>> maps = await db.query(
      tableWeek,
      where: 'device_id = ? AND timestamp >= ?',
      whereArgs: [deviceId, cutoffTimestamp],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => WeatherMonitoringRecord.fromMap(map)).toList();
  }

  /// Tự động xóa bản ghi quá 7 ngày trong bảng weather_week
  Future<int> autoDeleteWeekOlderThan7Days() async {
    final db = await _appDatabase.database;
    final cutoffTimestamp = DateTime.now()
        .subtract(const Duration(days: ApiConstants.cacheRetentionDays))
        .millisecondsSinceEpoch;

    return await db.delete(
      tableWeek,
      where: 'timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );
  }

  /// Xóa các bản ghi tương lai sai lệch trong bảng weather_week
  Future<int> purgeFutureWeekRecords() async {
    final db = await _appDatabase.database;
    final nowEpoch = DateTime.now().millisecondsSinceEpoch;
    return await db.delete(
      tableWeek,
      where: 'timestamp > ?',
      whereArgs: [nowEpoch + 600000],
    );
  }

  /// Đồng bộ lưu danh sách bản ghi 7 ngày và tự động dọn dẹp các bản ghi quá 7 ngày
  Future<void> saveWeekHistoryAndCleanup(
    List<WeatherMonitoringRecord> records,
  ) async {
    if (records.isNotEmpty) {
      await insertWeekBatch(records);
    }
    await autoDeleteWeekOlderThan7Days();
    await purgeFutureWeekRecords();
  }

  /// Đếm tổng số bản ghi hiện có trong bảng weather_week
  Future<int> countWeek({String? deviceId}) async {
    final db = await _appDatabase.database;
    final result = await db.rawQuery(
      deviceId != null
          ? 'SELECT COUNT(*) as total FROM $tableWeek WHERE device_id = ?'
          : 'SELECT COUNT(*) as total FROM $tableWeek',
      deviceId != null ? [deviceId] : null,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  // =========================================================================
  // 3. TƯƠNG THÍCH NGƯỢC (Backward Compatibility) & TIỆN ÍCH DỌN DẸP
  // =========================================================================

  Future<WeatherMonitoringRecord?> getLatestRecord({
    String deviceId = ApiConstants.defaultStationId,
  }) async {
    final db = await _appDatabase.database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableWeek,
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return WeatherMonitoringRecord.fromMap(maps.first);
  }

  Future<int> insertRecord(WeatherMonitoringRecord record) =>
      insertWeekRecord(record);

  Future<void> insertBatch(List<WeatherMonitoringRecord> records) =>
      insertWeekBatch(records);

  Future<List<WeatherMonitoringRecord>> getHistory7Days({
    String deviceId = ApiConstants.defaultStationId,
  }) =>
      getWeekHistory7Days(deviceId: deviceId);

  Future<int> autoDeleteOlderThan7Days() => autoDeleteWeekOlderThan7Days();

  Future<void> saveHistoryAndCleanup(List<WeatherMonitoringRecord> records) =>
      saveWeekHistoryAndCleanup(records);

  Future<int> count({String? deviceId}) => countWeek(deviceId: deviceId);

  /// Xóa toàn bộ dữ liệu ở cả 2 bảng (dùng khi reset app hoặc test)
  Future<void> clearAll() async {
    final db = await _appDatabase.database;
    await db.delete(tableInday);
    await db.delete(tableWeek);
  }
}
