import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/api_constants.dart';
import '../data/models/device_command_model.dart';
import '../data/models/device_config_model.dart';
import '../data/network/device_api_service.dart';
import '../data/network/dio_client.dart';
import '../data/repositories/device_repository.dart';

/// Provider Dio Client dùng chung
final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient();
});

/// Provider Device API Service
final deviceApiServiceProvider = Provider<DeviceApiService>((ref) {
  final dioClient = ref.watch(dioClientProvider);
  return DeviceApiService(dioClient);
});

/// Provider Device Repository
final deviceRepositoryProvider = Provider<DeviceRepository>((ref) {
  final apiService = ref.watch(deviceApiServiceProvider);
  return DeviceRepositoryImpl(apiService);
});

/// StateProvider lưu trữ mã trạm hiện tại đang được chọn
final selectedDeviceIdProvider = StateProvider<String>((ref) {
  return ApiConstants.defaultStationId;
});

// ==========================================
// 1. Quản lý trạng thái Command (Instant)
// ==========================================

class DeviceCommandState {
  final String? activeCommand; // 'led', 'buzzer', 'reboot'
  final String? lastSuccessMessage;
  final String? errorMessage;

  const DeviceCommandState({
    this.activeCommand,
    this.lastSuccessMessage,
    this.errorMessage,
  });

  bool get isLoading => activeCommand != null;

  DeviceCommandState copyWith({
    String? activeCommand,
    String? lastSuccessMessage,
    String? errorMessage,
    bool clearActiveCommand = false,
    bool clearMessages = false,
  }) {
    return DeviceCommandState(
      activeCommand: clearActiveCommand ? null : (activeCommand ?? this.activeCommand),
      lastSuccessMessage: clearMessages ? null : (lastSuccessMessage ?? this.lastSuccessMessage),
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class DeviceCommandNotifier extends StateNotifier<DeviceCommandState> {
  final Ref ref;

  DeviceCommandNotifier(this.ref) : super(const DeviceCommandState());

  /// Gửi lệnh điều khiển ngay lập tức khi ấn nút
  Future<bool> sendInstantCommand(String cmd, {String? arg, String? labelVi}) async {
    final deviceId = ref.read(selectedDeviceIdProvider);
    final repo = ref.read(deviceRepositoryProvider);

    state = state.copyWith(
      activeCommand: cmd,
      clearMessages: true,
    );

    try {
      final success = await repo.sendCommand(
        deviceId: deviceId,
        command: DeviceCommandModel(cmd: cmd, arg: arg),
      );

      final displayName = labelVi ?? cmd;
      if (success) {
        state = state.copyWith(
          clearActiveCommand: true,
          lastSuccessMessage: 'Đã gửi lệnh $displayName tới trạm $deviceId',
        );
        return true;
      } else {
        state = state.copyWith(
          clearActiveCommand: true,
          errorMessage: 'Trạm $deviceId không tiếp nhận lệnh "$displayName".',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        clearActiveCommand: true,
        errorMessage: 'Lỗi khi gửi lệnh "$cmd": ${e.toString()}',
      );
      return false;
    }
  }

  void clearStatus() {
    state = state.copyWith(clearMessages: true);
  }
}

final deviceCommandProvider =
    StateNotifierProvider<DeviceCommandNotifier, DeviceCommandState>((ref) {
  return DeviceCommandNotifier(ref);
});

// ==========================================
// 2. Quản lý trạng thái Config (Form & Save)
// ==========================================

class DeviceConfigState {
  final DeviceConfigModel config;
  final bool isSaving;
  final String? lastSuccessMessage;
  final String? errorMessage;

  const DeviceConfigState({
    required this.config,
    this.isSaving = false,
    this.lastSuccessMessage,
    this.errorMessage,
  });

  DeviceConfigState copyWith({
    DeviceConfigModel? config,
    bool? isSaving,
    String? lastSuccessMessage,
    String? errorMessage,
    bool clearMessages = false,
  }) {
    return DeviceConfigState(
      config: config ?? this.config,
      isSaving: isSaving ?? this.isSaving,
      lastSuccessMessage: clearMessages ? null : (lastSuccessMessage ?? this.lastSuccessMessage),
      errorMessage: clearMessages ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class DeviceConfigNotifier extends StateNotifier<DeviceConfigState> {
  final Ref ref;

  DeviceConfigNotifier(this.ref)
      : super(
          DeviceConfigState(
            config: DeviceConfigModel.initialDefault(),
          ),
        );

  void updateTempMax(double? value) {
    state = state.copyWith(
      config: state.config.copyWith(tempMax: value),
      clearMessages: true,
    );
  }

  void updateTempMin(double? value) {
    state = state.copyWith(
      config: state.config.copyWith(tempMin: value),
      clearMessages: true,
    );
  }

  void updateHumiMax(double? value) {
    state = state.copyWith(
      config: state.config.copyWith(humiMax: value),
      clearMessages: true,
    );
  }

  void updateWindMax(double? value) {
    state = state.copyWith(
      config: state.config.copyWith(windMax: value),
      clearMessages: true,
    );
  }

  void updateRainMax(double? value) {
    state = state.copyWith(
      config: state.config.copyWith(rainMax: value),
      clearMessages: true,
    );
  }

  void toggleAutoWarning(bool value) {
    state = state.copyWith(
      config: state.config.copyWith(autoWarning: value),
      clearMessages: true,
    );
  }

  void toggleBuzzer(bool value) {
    state = state.copyWith(
      config: state.config.copyWith(buzzer: value),
      clearMessages: true,
    );
  }

  /// Gửi HTTP request lưu cấu hình
  Future<bool> saveConfig() async {
    final deviceId = ref.read(selectedDeviceIdProvider);
    final repo = ref.read(deviceRepositoryProvider);

    state = state.copyWith(
      isSaving: true,
      clearMessages: true,
    );

    try {
      final success = await repo.updateConfig(
        deviceId: deviceId,
        config: state.config,
      );

      if (success) {
        state = state.copyWith(
          isSaving: false,
          lastSuccessMessage: 'Đã lưu cấu hình tới trạm $deviceId',
        );
        return true;
      } else {
        state = state.copyWith(
          isSaving: false,
          errorMessage: 'Trạm $deviceId không tiếp nhận cấu hình mới.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Lưu cấu hình thất bại: ${e.toString()}',
      );
      return false;
    }
  }

  void clearStatus() {
    state = state.copyWith(clearMessages: true);
  }
}

final deviceConfigProvider =
    StateNotifierProvider<DeviceConfigNotifier, DeviceConfigState>((ref) {
  return DeviceConfigNotifier(ref);
});
