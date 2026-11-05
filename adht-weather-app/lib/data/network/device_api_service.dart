import 'package:dio/dio.dart';
import '../../core/constants/api_constants.dart';
import '../models/device_command_model.dart';
import '../models/device_config_model.dart';
import 'api_exceptions.dart';
import 'api_response.dart';
import 'dio_client.dart';

/// Dịch vụ giao tiếp API điều khiển trạm thiết bị qua Backend Gateway
class DeviceApiService {
  final DioClient _dioClient;

  DeviceApiService(this._dioClient);

  Dio get _dio => _dioClient.dio;

  /// Gửi lệnh điều khiển phần cứng xuống thiết bị qua POST /devices/:id/command
  Future<ApiResponse<Map<String, dynamic>>> sendCommand({
    required String deviceId,
    required DeviceCommandModel command,
  }) async {
    try {
      final response = await _dio.post(
        ApiConstants.endpointDeviceCommand(deviceId),
        data: command.toJson(),
      );

      return ApiResponse.fromJson(
        response.data as Map<String, dynamic>,
        (dataJson) => dataJson as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  /// Cập nhật cấu hình ngưỡng cảnh báo qua PUT /devices/:id/config
  Future<ApiResponse<Map<String, dynamic>>> updateConfig({
    required String deviceId,
    required DeviceConfigModel config,
  }) async {
    try {
      final response = await _dio.put(
        ApiConstants.endpointDeviceConfig(deviceId),
        data: config.toJson(),
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
