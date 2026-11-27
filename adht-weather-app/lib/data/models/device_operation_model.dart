import 'device_config_model.dart';

enum OperationLifecycleStatus {
  queued,
  published,
  accepted,
  persisted,
  applied,
  failed,
  expired,
  unknown;

  static OperationLifecycleStatus fromRaw(String? raw) {
    switch (raw) {
      case 'queued':
        return OperationLifecycleStatus.queued;
      case 'published':
        return OperationLifecycleStatus.published;
      case 'accepted':
        return OperationLifecycleStatus.accepted;
      case 'persisted':
        return OperationLifecycleStatus.persisted;
      case 'applied':
        return OperationLifecycleStatus.applied;
      case 'failed':
      case 'rejected':
        return OperationLifecycleStatus.failed;
      case 'expired':
        return OperationLifecycleStatus.expired;
      default:
        return OperationLifecycleStatus.unknown;
    }
  }

  bool get isTerminal =>
      this == OperationLifecycleStatus.applied ||
      this == OperationLifecycleStatus.failed ||
      this == OperationLifecycleStatus.expired;

  String get labelVi {
    switch (this) {
      case OperationLifecycleStatus.queued:
        return 'Đang xếp hàng gửi';
      case OperationLifecycleStatus.published:
        return 'Đã gửi qua broker (chờ trạm xác nhận)';
      case OperationLifecycleStatus.accepted:
        return 'Trạm đã tiếp nhận';
      case OperationLifecycleStatus.persisted:
        return 'Trạm đã lưu NVS';
      case OperationLifecycleStatus.applied:
        return 'Trạm đã áp dụng';
      case OperationLifecycleStatus.failed:
        return 'Thực thi thất bại';
      case OperationLifecycleStatus.expired:
        return 'Đã hết hạn';
      case OperationLifecycleStatus.unknown:
        return 'Chưa rõ trạng thái';
    }
  }
}

class DeviceOperationResult {
  final String? operationId;
  final OperationLifecycleStatus status;
  final int? desiredVersion;
  final String? expiresAt;
  final String? errorMessage;

  const DeviceOperationResult({
    this.operationId,
    required this.status,
    this.desiredVersion,
    this.expiresAt,
    this.errorMessage,
  });

  factory DeviceOperationResult.fromJson(Map<String, dynamic> json) {
    final rawStatus =
        (json['operation_status'] as String?) ?? (json['status'] as String?);
    return DeviceOperationResult(
      operationId: json['operation_id'] as String?,
      status: OperationLifecycleStatus.fromRaw(rawStatus),
      desiredVersion: (json['desired_version'] as num?)?.toInt(),
      expiresAt: json['expires_at'] as String?,
      errorMessage: json['error_message'] as String?,
    );
  }
}

class StationStateSnapshot {
  final String deviceId;
  final int desiredVersion;
  final DeviceConfigModel desiredConfig;
  final int reportedVersion;
  final DeviceConfigModel? reportedConfig;

  const StationStateSnapshot({
    required this.deviceId,
    required this.desiredVersion,
    required this.desiredConfig,
    required this.reportedVersion,
    this.reportedConfig,
  });

  factory StationStateSnapshot.fromJson(Map<String, dynamic> json) {
    final desiredJson = json['desired_config'] as Map<String, dynamic>?;
    final reportedJson = json['reported_config'] as Map<String, dynamic>?;
    return StationStateSnapshot(
      deviceId: json['device_id'] as String? ?? '',
      desiredVersion: (json['desired_version'] as num?)?.toInt() ?? 0,
      desiredConfig: desiredJson != null
          ? DeviceConfigModel.fromJson(desiredJson)
          : DeviceConfigModel.initialDefault(),
      reportedVersion: (json['reported_version'] as num?)?.toInt() ?? 0,
      reportedConfig:
          reportedJson != null ? DeviceConfigModel.fromJson(reportedJson) : null,
    );
  }
}
