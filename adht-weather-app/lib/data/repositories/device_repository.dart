import '../models/device_command_model.dart';
import '../models/device_config_model.dart';
import '../models/device_operation_model.dart';
import '../network/device_api_service.dart';

/// Interface quản lý giao tiếp thiết bị
abstract class DeviceRepository {
  Future<bool> sendCommand({
    required String deviceId,
    required DeviceCommandModel command,
  });

  Future<bool> updateConfig({
    required String deviceId,
    required DeviceConfigModel config,
  });

  Future<DeviceOperationResult> sendCommandOperation({
    required String deviceId,
    required DeviceCommandModel command,
    String? requestId,
  });

  Future<DeviceOperationResult> updateConfigOperation({
    required String deviceId,
    required DeviceConfigModel config,
    int? expectedVersion,
    String? requestId,
  });

  Future<StationStateSnapshot> getStationState(String deviceId);

  Future<DeviceOperationResult> getOperationStatus({
    required String deviceId,
    required String operationId,
  });
}

/// Hiện thực hóa DeviceRepository giao tiếp qua HTTP Backend Gateway
class DeviceRepositoryImpl implements DeviceRepository {
  final DeviceApiService _apiService;

  DeviceRepositoryImpl(this._apiService);

  @override
  Future<bool> sendCommand({
    required String deviceId,
    required DeviceCommandModel command,
  }) async {
    final op = await sendCommandOperation(deviceId: deviceId, command: command);
    return op.status != OperationLifecycleStatus.failed &&
        op.status != OperationLifecycleStatus.expired;
  }

  @override
  Future<bool> updateConfig({
    required String deviceId,
    required DeviceConfigModel config,
  }) async {
    final op = await updateConfigOperation(deviceId: deviceId, config: config);
    return op.status != OperationLifecycleStatus.failed &&
        op.status != OperationLifecycleStatus.expired;
  }

  @override
  Future<DeviceOperationResult> sendCommandOperation({
    required String deviceId,
    required DeviceCommandModel command,
    String? requestId,
  }) async {
    final response = await _apiService.sendCommand(
      deviceId: deviceId,
      command: command,
      requestId: requestId,
    );
    return DeviceOperationResult.fromJson(response.data);
  }

  @override
  Future<DeviceOperationResult> updateConfigOperation({
    required String deviceId,
    required DeviceConfigModel config,
    int? expectedVersion,
    String? requestId,
  }) async {
    final response = await _apiService.updateConfig(
      deviceId: deviceId,
      config: config,
      expectedVersion: expectedVersion,
      requestId: requestId,
    );
    return DeviceOperationResult.fromJson(response.data);
  }

  @override
  Future<StationStateSnapshot> getStationState(String deviceId) {
    return _apiService.fetchStationState(deviceId);
  }

  @override
  Future<DeviceOperationResult> getOperationStatus({
    required String deviceId,
    required String operationId,
  }) {
    return _apiService.fetchOperationStatus(
      deviceId: deviceId,
      operationId: operationId,
    );
  }
}
