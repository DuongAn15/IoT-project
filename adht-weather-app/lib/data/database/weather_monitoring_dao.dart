import 'package:sqflite/sqflite.dart';
import '../../core/constants/api_constants.dart';
import '../../core/utils/date_time_formatter.dart';
import '../models/weather_monitoring_record.dart';
import 'app_database.dart';

/// DAO phụ trách truy vấn, lưu trữ và tự động dọn dẹp lịch sử thời tiết trong SQLite
class WeatherMonitoringDao {
  final AppDatabase _appDatabase;

  WeatherMonitoringDao([AppDatabase? database])
      : _appDatabase = database ?? AppDatabase.instance;

  String get _tableName => ApiConstants.tableWeatherMonitoring;

  /// Thêm hoặc ghi đè một bản ghi đo đạc vào bảng
  Future<int> insertRecord(WeatherMonitoringRecord record) async {
    final db = await _appDatabase.database;
    return await db.insert(
      _tableName,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Thêm danh sách bản ghi theo Batch Transaction để tối ưu hiệu năng
  Future<void> insertBatch(List<WeatherMonitoringRecord> records) async {
    if (records.isEmpty) return;

    final db = await _appDatabase.database;
    final batch = db.batch();

    for (final record in records) {
      batch.insert(
        _tableName,
        record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
  }

  /// Lấy danh sách bản ghi lịch sử trong vòng 7 ngày gần nhất của trạm
  /// Mặc định trạm quan trắc là `adht_weather_01`
  Future<List<WeatherMonitoringRecord>> getHistory7Days({
    String deviceId = ApiConstants.defaultStationId,
  }) async {
    final db = await _appDatabase.database;
    final cutoffTimestamp = DateTimeFormatter.currentGmt7Time()
        .subtract(const Duration(days: ApiConstants.cacheRetentionDays))
        .millisecondsSinceEpoch;

    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'device_id = ? AND timestamp >= ?',
      whereArgs: [deviceId, cutoffTimestamp],
      orderBy: 'timestamp ASC',
    );

    return maps.map((map) => WeatherMonitoringRecord.fromMap(map)).toList();
  }

  /// Cơ chế tự động xóa bản ghi quá 7 ngày tính từ thời điểm hiện tại
  /// Trả về số lượng bản ghi đã được xóa
  Future<int> autoDeleteOlderThan7Days() async {
    return await deleteRecordsOlderThan(
      duration: const Duration(days: ApiConstants.cacheRetentionDays),
    );
  }

  /// Xóa bản ghi cũ hơn một khoảng thời gian nhất định (tính từ thời điểm gọi hàm)
  Future<int> deleteRecordsOlderThan({
    Duration duration = const Duration(days: ApiConstants.cacheRetentionDays),
  }) async {
    final db = await _appDatabase.database;
    final cutoffTimestamp =
        DateTimeFormatter.currentGmt7Time().subtract(duration).millisecondsSinceEpoch;

    final deletedCount = await db.delete(
      _tableName,
      where: 'timestamp < ?',
      whereArgs: [cutoffTimestamp],
    );

    return deletedCount;
  }

  /// Xóa các bản ghi có timestamp trong tương lai (đề phòng sai lệch dữ liệu cũ)
  Future<int> purgeFutureRecords() async {
    final db = await _appDatabase.database;
    final nowGmt7Epoch =
        DateTimeFormatter.currentGmt7Time().millisecondsSinceEpoch;
    // Cho phép dung sai 10 phút trôi đồng hồ
    return await db.delete(
      _tableName,
      where: 'timestamp > ?',
      whereArgs: [nowGmt7Epoch + 600000],
    );
  }

  /// Đồng bộ lưu danh sách bản ghi mới và tự động thực thi dọn dẹp các bản ghi quá 7 ngày
  Future<void> saveHistoryAndCleanup(
    List<WeatherMonitoringRecord> records,
  ) async {
    if (records.isNotEmpty) {
      await insertBatch(records);
    }
    await autoDeleteOlderThan7Days();
    await purgeFutureRecords();
  }

  /// Lấy bản ghi mới nhất của trạm
  Future<WeatherMonitoringRecord?> getLatestRecord({
    String deviceId = ApiConstants.defaultStationId,
  }) async {
    final db = await _appDatabase.database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return WeatherMonitoringRecord.fromMap(maps.first);
  }

  /// Lấy toàn bộ bản ghi theo trạm (hoặc tất cả các trạm)
  Future<List<WeatherMonitoringRecord>> getAllRecords({
    String? deviceId,
    int? limit,
  }) async {
    final db = await _appDatabase.database;
    final List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: deviceId != null ? 'device_id = ?' : null,
      whereArgs: deviceId != null ? [deviceId] : null,
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return maps.map((map) => WeatherMonitoringRecord.fromMap(map)).toList();
  }

  /// Đếm tổng số bản ghi hiện có trong bảng
  Future<int> count({String? deviceId}) async {
    final db = await _appDatabase.database;
    final result = await db.rawQuery(
      deviceId != null
          ? 'SELECT COUNT(*) as total FROM $_tableName WHERE device_id = ?'
          : 'SELECT COUNT(*) as total FROM $_tableName',
      deviceId != null ? [deviceId] : null,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Xóa toàn bộ dữ liệu bảng (dùng khi xóa cache hoặc reset ứng dụng)
  Future<int> clearAll() async {
    final db = await _appDatabase.database;
    return await db.delete(_tableName);
  }
}
