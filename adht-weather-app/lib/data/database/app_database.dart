import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../core/constants/api_constants.dart';

/// Quản lý vòng đời và cấu trúc cơ sở dữ liệu SQLite cục bộ của ứng dụng
class AppDatabase {
  static final AppDatabase instance = AppDatabase._internal();

  Database? _database;
  final DatabaseFactory? _databaseFactory;

  AppDatabase._internal() : _databaseFactory = null;

  /// Constructor phục vụ Dependency Injection hoặc Unit Testing
  AppDatabase.withFactory(DatabaseFactory factory) : _databaseFactory = factory;

  /// Constructor sử dụng database đã mở sẵn (dùng cho unit test in-memory)
  AppDatabase.withDatabase(Database db)
      : _database = db,
        _databaseFactory = null;

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final factory = _databaseFactory ?? databaseFactory;
    final databasesPath = await factory.getDatabasesPath();
    final path = p.join(databasesPath, ApiConstants.databaseName);

    return await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: ApiConstants.databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 1. Bảng weather_inday: Lưu dữ liệu trong ngày (chuỗi 24h, tự động xóa bản ghi quá 24h)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${ApiConstants.tableWeatherInday} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        temperature REAL NOT NULL,
        humidity REAL NOT NULL,
        rainfall REAL NOT NULL,
        rainfall_mm REAL,
        wind_speed REAL NOT NULL,
        source TEXT,
        rain_quality TEXT,
        sample_count INTEGER,
        temp_min REAL,
        temp_max REAL,
        coverage REAL,
        revision INTEGER,
        is_partial INTEGER,
        recorded_at TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        UNIQUE(device_id, recorded_at) ON CONFLICT REPLACE
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_weather_inday_device_time 
      ON ${ApiConstants.tableWeatherInday} (device_id, timestamp);
    ''');

    // 2. Bảng weather_week: Lưu lịch sử 7 ngày (tự động xóa bản ghi quá 7 ngày)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${ApiConstants.tableWeatherWeek} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL,
        temperature REAL NOT NULL,
        humidity REAL NOT NULL,
        rainfall REAL NOT NULL,
        rainfall_mm REAL,
        wind_speed REAL NOT NULL,
        source TEXT,
        rain_quality TEXT,
        sample_count INTEGER,
        temp_min REAL,
        temp_max REAL,
        coverage REAL,
        revision INTEGER,
        is_partial INTEGER,
        recorded_at TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        UNIQUE(device_id, recorded_at) ON CONFLICT REPLACE
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_weather_week_device_time 
      ON ${ApiConstants.tableWeatherWeek} (device_id, timestamp);
    ''');

    await _createSyncCursorsTable(db);
  }

  Future<void> _createSyncCursorsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${ApiConstants.tableSyncCursors} (
        device_id TEXT NOT NULL,
        series TEXT NOT NULL,
        last_synced_at TEXT NOT NULL,
        PRIMARY KEY (device_id, series)
      );
    ''');
  }

  Future<void> _addColumnIfMissing(
    Database db,
    String tableName,
    String columnName,
    String columnType,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($tableName)');
    final exists = cols.any((col) => col['name'] == columnName);
    if (!exists) {
      await db.execute(
        'ALTER TABLE $tableName ADD COLUMN $columnName $columnType;',
      );
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _onCreate(db, newVersion);
    }
    if (oldVersion < 3) {
      for (final table in [
        ApiConstants.tableWeatherInday,
        ApiConstants.tableWeatherWeek,
      ]) {
        await _addColumnIfMissing(db, table, 'rainfall_mm', 'REAL');
        await _addColumnIfMissing(db, table, 'source', 'TEXT');
        await _addColumnIfMissing(db, table, 'rain_quality', 'TEXT');
        await _addColumnIfMissing(db, table, 'sample_count', 'INTEGER');
        await _addColumnIfMissing(db, table, 'temp_min', 'REAL');
        await _addColumnIfMissing(db, table, 'temp_max', 'REAL');
        await _addColumnIfMissing(db, table, 'coverage', 'REAL');
        await _addColumnIfMissing(db, table, 'revision', 'INTEGER');
        await _addColumnIfMissing(db, table, 'is_partial', 'INTEGER');
      }
      await _createSyncCursorsTable(db);
    }
  }

  /// Đóng cơ sở dữ liệu
  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }
}
