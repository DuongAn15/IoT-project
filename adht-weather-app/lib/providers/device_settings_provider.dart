import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/api_constants.dart';
import '../data/models/device_command_model.dart';
import '../data/models/device_config_model.dart';
import '../data/models/device_operation_model.dart';
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
  final String? activeOperationId;
  final OperationLifecycleStatus? operationStatus;
  final String? lastSuccessMessage;
  final String? errorMessage;

  const DeviceCommandState({
    this.activeCommand,
    this.activeOperationId,
    this.operationStatus,
    this.lastSuccessMessage,
    this.errorMessage,
  });

  bool get isLoading => activeCommand != null;

  DeviceCommandState copyWith({
    String? activeCommand,
    String? activeOperationId,
    OperationLifecycleStatus? operationStatus,
    String? lastSuccessMessage,
    String? errorMessage,
    bool clearActiveCommand = false,
    bool clearMessages = false,
  }) {
    return DeviceCommandState(
      activeCommand: clearActiveCommand ? null : (activeCommand ?? this.activeCommand),
      activeOperationId: activeOperationId ?? this.activeOperationId,
      operationStatus: operationStatus ?? this.operationStatus,
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
    final requestId = 'cmd-${DateTime.now().microsecondsSinceEpoch}';

    state = state.copyWith(
      activeCommand: cmd,
      activeOperationId: requestId,
      operationStatus: OperationLifecycleStatus.queued,
      clearMessages: true,
    );

    try {
      final result = await repo.sendCommandOperation(
        deviceId: deviceId,
        command: DeviceCommandModel(cmd: cmd, arg: arg),
        requestId: requestId,
      );

      final displayName = labelVi ?? cmd;
      if (result.status != OperationLifecycleStatus.failed &&
          result.status != OperationLifecycleStatus.expired) {
        state = state.copyWith(
          clearActiveCommand: true,
          activeOperationId: result.operationId ?? requestId,
          operationStatus: result.status,
          lastSuccessMessage: '$displayName ($deviceId): ${result.status.labelVi}',
        );
        return true;
      } else {
        state = state.copyWith(
          clearActiveCommand: true,
          activeOperationId: result.operationId ?? requestId,
          operationStatus: result.status,
          errorMessage: result.errorMessage ??
              'Trạm $deviceId không tiếp nhận lệnh "$displayName".',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        clearActiveCommand: true,
        operationStatus: OperationLifecycleStatus.unknown,
        errorMessage: 'Mất kết nối khi gửi "$cmd" (trạng thái chưa rõ): ${e.toString()}',
      );
      return false;
    }
  }

  Future<void> reconcileActiveOperation() async {
    final opId = state.activeOperationId;
    if (opId == null || opId.isEmpty) return;
    final deviceId = ref.read(selectedDeviceIdProvider);
    final repo = ref.read(deviceRepositoryProvider);
    try {
      final result = await repo.getOperationStatus(
        deviceId: deviceId,
        operationId: opId,
      );
      state = state.copyWith(
        operationStatus: result.status,
        lastSuccessMessage: result.status == OperationLifecycleStatus.applied
            ? 'Trạm $deviceId đã thực thi lệnh'
            : null,
        errorMessage: result.status == OperationLifecycleStatus.failed ||
                result.status == OperationLifecycleStatus.expired
            ? (result.errorMessage ?? result.status.labelVi)
            : null,
      );
    } catch (_) {
      state = state.copyWith(operationStatus: OperationLifecycleStatus.unknown);
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
  final int desiredVersion;
  final int reportedVersion;
  final String? activeOperationId;
  final OperationLifecycleStatus? operationStatus;
  final bool isSaving;
  final String? lastSuccessMessage;
  final String? errorMessage;

  const DeviceConfigState({
    required this.config,
    this.desiredVersion = 0,
    this.reportedVersion = 0,
    this.activeOperationId,
    this.operationStatus,
    this.isSaving = false,
    this.lastSuccessMessage,
    this.errorMessage,
  });

  DeviceConfigState copyWith({
    DeviceConfigModel? config,
    int? desiredVersion,
    int? reportedVersion,
    String? activeOperationId,
    OperationLifecycleStatus? operationStatus,
    bool? isSaving,
    String? lastSuccessMessage,
    String? errorMessage,
    bool clearMessages = false,
  }) {
    return DeviceConfigState(
      config: config ?? this.config,
      desiredVersion: desiredVersion ?? this.desiredVersion,
      reportedVersion: reportedVersion ?? this.reportedVersion,
      activeOperationId: activeOperationId ?? this.activeOperationId,
      operationStatus: operationStatus ?? this.operationStatus,
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

  Future<void> loadStationState(String deviceId) async {
    final repo = ref.read(deviceRepositoryProvider);
    try {
      final snapshot = await repo.getStationState(deviceId);
      state = state.copyWith(
        config: snapshot.desiredConfig,
        desiredVersion: snapshot.desiredVersion,
        reportedVersion: snapshot.reportedVersion,
      );
    } catch (_) {
      // Giữ config hiện tại nếu offline
    }
  }

  /// Gửi HTTP request lưu cấu hình
  Future<bool> saveConfig() async {
    final deviceId = ref.read(selectedDeviceIdProvider);
    final repo = ref.read(deviceRepositoryProvider);
    final requestId = 'cfg-${DateTime.now().microsecondsSinceEpoch}';

    state = state.copyWith(
      isSaving: true,
      activeOperationId: requestId,
      operationStatus: OperationLifecycleStatus.queued,
      clearMessages: true,
    );

    try {
      final result = await repo.updateConfigOperation(
        deviceId: deviceId,
        config: state.config,
        expectedVersion: state.desiredVersion,
        requestId: requestId,
      );

      if (result.status != OperationLifecycleStatus.failed &&
          result.status != OperationLifecycleStatus.expired) {
        state = state.copyWith(
          isSaving: false,
          desiredVersion: result.desiredVersion ?? state.desiredVersion,
          activeOperationId: result.operationId ?? requestId,
          operationStatus: result.status,
          lastSuccessMessage: 'Cấu hình $deviceId: ${result.status.labelVi}',
        );
        return true;
      } else {
        state = state.copyWith(
          isSaving: false,
          activeOperationId: result.operationId ?? requestId,
          operationStatus: result.status,
          errorMessage: result.errorMessage ??
              'Trạm $deviceId không tiếp nhận cấu hình mới.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        operationStatus: OperationLifecycleStatus.unknown,
        errorMessage: 'Lưu cấu hình chưa rõ kết quả: ${e.toString()}',
      );
      return false;
    }
  }

  Future<void> reconcileActiveConfig() async {
    final deviceId = ref.read(selectedDeviceIdProvider);
    final repo = ref.read(deviceRepositoryProvider);
    try {
      final snapshot = await repo.getStationState(deviceId);
      OperationLifecycleStatus? opStatus = state.operationStatus;
      final opId = state.activeOperationId;
      if (opId != null && opId.isNotEmpty) {
        try {
          final op = await repo.getOperationStatus(
            deviceId: deviceId,
            operationId: opId,
          );
          opStatus = op.status;
        } catch (_) {}
      }
      state = state.copyWith(
        desiredVersion: snapshot.desiredVersion,
        reportedVersion: snapshot.reportedVersion,
        operationStatus: opStatus,
      );
    } catch (_) {
      state = state.copyWith(operationStatus: OperationLifecycleStatus.unknown);
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
