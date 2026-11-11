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
        wind_speed REAL NOT NULL,
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
        wind_speed REAL NOT NULL,
        recorded_at TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        UNIQUE(device_id, recorded_at) ON CONFLICT REPLACE
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_weather_week_device_time 
      ON ${ApiConstants.tableWeatherWeek} (device_id, timestamp);
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _onCreate(db, newVersion);
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
