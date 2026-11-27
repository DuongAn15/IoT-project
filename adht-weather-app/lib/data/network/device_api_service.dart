import 'package:dio/dio.dart';
import '../../core/constants/api_constants.dart';
import '../models/device_command_model.dart';
import '../models/device_config_model.dart';
import '../models/device_operation_model.dart';
import '../models/station_info.dart';
import 'api_exceptions.dart';
import 'api_response.dart';
import 'dio_client.dart';

/// Dịch vụ giao tiếp API điều khiển trạm thiết bị qua Backend Gateway
class DeviceApiService {
  final DioClient _dioClient;

  DeviceApiService(this._dioClient);

  Dio get _dio => _dioClient.dio;

  /// Tải danh sách trạm từ GET /devices
  Future<List<StationInfo>> fetchDevices() async {
    try {
      final response = await _dio.get('/devices');
      final body = response.data as Map<String, dynamic>;
      final rawList = body['data'] as List<dynamic>? ?? [];
      return rawList
          .whereType<Map<String, dynamic>>()
          .map(StationInfo.fromJson)
          .where((s) => s.deviceId.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  /// Gửi lệnh điều khiển phần cứng xuống thiết bị qua POST /devices/:id/command
  Future<ApiResponse<Map<String, dynamic>>> sendCommand({
    required String deviceId,
    required DeviceCommandModel command,
    String? requestId,
  }) async {
    try {
      final body = {
        ...command.toJson(),
        if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
      };
      final response = await _dio.post(
        ApiConstants.endpointDeviceCommand(deviceId),
        data: body,
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
    int? expectedVersion,
    String? requestId,
  }) async {
    try {
      final body = {
        ...config.toJson(),
        'expected_version': ?expectedVersion,
        if (requestId != null && requestId.isNotEmpty) 'request_id': requestId,
      };
      final response = await _dio.put(
        ApiConstants.endpointDeviceConfig(deviceId),
        data: body,
      );

      return ApiResponse.fromJson(
        response.data as Map<String, dynamic>,
        (dataJson) => dataJson as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  /// Lấy desired/reported state từ GET /devices/:id/state
  Future<StationStateSnapshot> fetchStationState(String deviceId) async {
    try {
      final response = await _dio.get(ApiConstants.endpointDeviceState(deviceId));
      final body = response.data as Map<String, dynamic>;
      final payload = (body['data'] as Map<String, dynamic>?) ?? body;
      return StationStateSnapshot.fromJson(payload);
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }

  /// Lấy trạng thái một operation từ GET /devices/:id/operations/:operationId
  Future<DeviceOperationResult> fetchOperationStatus({
    required String deviceId,
    required String operationId,
  }) async {
    try {
      final response = await _dio.get(
        ApiConstants.endpointDeviceOperation(deviceId, operationId),
      );
      final body = response.data as Map<String, dynamic>;
      final payload = (body['data'] as Map<String, dynamic>?) ?? body;
      return DeviceOperationResult.fromJson(payload);
    } on DioException catch (e) {
      throw handleDioError(e);
    }
  }
}
