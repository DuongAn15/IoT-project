import 'package:dio/dio.dart';
import '../../core/constants/api_constants.dart';
import 'api_exceptions.dart';
import 'api_response.dart';
import 'dio_client.dart';

/// Dịch vụ giao tiếp API lấy số liệu thời tiết từ Backend Gateway
class WeatherApiService {
  final DioClient _dioClient;

  WeatherApiService(this._dioClient);

  Dio get _dio => _dioClient.dio;

  /// Gọi GET /weather/latest?device_id=...
  Future<ApiResponse<Map<String, dynamic>?>> fetchLatestWeather(
    String deviceId,
  ) async {
    try {
      final response = await _dio.get(
        ApiConstants.endpointWeatherLatest,
        queryParameters: {'device_id': deviceId},
      );

      return ApiResponse.fromJson(
        response.data as Map<String, dynamic>,
        (dataJson) => dataJson as Map<String, dynamic>?,
      );
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  /// Gọi GET /weather/history?device_id=...&range=...
  Future<ApiResponse<Map<String, dynamic>>> fetchHistory({
    required String deviceId,
    required String range,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.endpointWeatherHistory,
        queryParameters: {
          'device_id': deviceId,
          'range': range,
        },
      );

      return ApiResponse.fromJson(
        response.data as Map<String, dynamic>,
        (dataJson) => dataJson as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }
}
