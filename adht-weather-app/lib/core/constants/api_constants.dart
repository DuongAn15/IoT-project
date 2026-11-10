/// Cấu hình và hằng số kết nối cho Trạm Quan Trắc & Backend Gateway API
abstract class ApiConstants {
  static const String defaultStationId = 'adht_weather_01';
  static const String defaultStationName = 'Trạm Quan Trắc IoT 01 - Trung Tâm';
  static const String defaultLocation = 'Đà Nẵng, Việt Nam';

  /// Danh sách các trạm thực tế theo định danh Backend / MQTT
  static const Map<String, String> deviceStationMap = {
    'adht_weather_01': 'Trạm IoT 01 - Trung Tâm',
    'adht_weather_02': 'Trạm IoT 02 - Bán Đảo Sơn Trà',
    'adht_weather_03': 'Trạm IoT 03 - Hòa Vang',
  };

  static const List<String> availableStations = [
    'Trạm IoT 01 - Trung Tâm',
    'Trạm IoT 02 - Bán Đảo Sơn Trà',
    'Trạm IoT 03 - Hòa Vang',
  ];

  /// Base URL kết nối Backend Gateway
  // static const String defaultBaseUrl = 'http://localhost:8000/api';
  static const String defaultBaseUrl = 'http://192.168.100.29:8000/api';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);

  // Device Endpoints
  static String endpointDeviceCommand(String id) => '/devices/$id/command';
  static String endpointDeviceConfig(String id) => '/devices/$id/config';

  // Weather Endpoints
  static const String endpointWeatherLatest = '/weather/latest';
  static const String endpointWeatherHistory = '/weather/history';
  static const String endpointWeatherForecast = '/weather/forecast';
  static const String endpointNotificationsRegister =
      '/notifications/register-token';

  // Cấu hình lưu trữ SQLite
  static const String databaseName = 'weather_monitoring.db';
  static const int databaseVersion = 1;
  static const String tableReadings = 'weather_readings';
}
