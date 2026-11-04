/// Cấu hình và hằng số kết nối cho Trạm Quan Trắc & API
abstract class ApiConstants {
  static const String defaultStationId = 'STATION_001';
  static const String defaultStationName = 'Trạm Quan Trắc IoT Trung Tâm';
  static const String defaultLocation = 'Đà Nẵng, Việt Nam';

  // API Config (sẵn sàng khi kết nối backend thật)
  static const String defaultBaseUrl = 'http://192.168.1.100:8080/api/v1';
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);

  // Endpoint paths
  static const String endpointCurrent = '/weather/current';
  static const String endpointIntraDay = '/weather/intraday';
  static const String endpoint7Days = '/weather/7days';

  // Cấu hình lưu trữ SQLite
  static const String databaseName = 'weather_monitoring.db';
  static const int databaseVersion = 1;
  static const String tableReadings = 'weather_readings';
}
