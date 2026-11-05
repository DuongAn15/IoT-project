import '../models/device_command_model.dart';
import '../models/device_config_model.dart';
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
    final response = await _apiService.sendCommand(
      deviceId: deviceId,
      command: command,
    );
    final status = response.data['status'] as String?;
    return status == 'success';
  }

  @override
  Future<bool> updateConfig({
    required String deviceId,
    required DeviceConfigModel config,
  }) async {
    final response = await _apiService.updateConfig(
      deviceId: deviceId,
      config: config,
    );
    final status = response.data['status'] as String?;
    return status == 'success';
  }
}
