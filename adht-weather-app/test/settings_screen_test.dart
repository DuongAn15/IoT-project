import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_monitoring/data/models/device_command_model.dart';
import 'package:weather_monitoring/data/models/device_config_model.dart';
import 'package:weather_monitoring/data/models/device_operation_model.dart';
import 'package:weather_monitoring/data/repositories/device_repository.dart';
import 'package:weather_monitoring/providers/device_settings_provider.dart';
import 'package:weather_monitoring/views/screens/settings_screen.dart';

void main() {
  group('Device Models Unit Tests', () {
    test('DeviceCommandModel serialization/deserialization', () {
      const command = DeviceCommandModel(cmd: 'buzzer', arg: '500');
      final json = command.toJson();

      expect(json['cmd'], equals('buzzer'));
      expect(json['arg'], equals('500'));

      final fromJson = DeviceCommandModel.fromJson(json);
      expect(fromJson.cmd, equals('buzzer'));
      expect(fromJson.arg, equals('500'));
    });

    test('DeviceConfigModel serialization/deserialization', () {
      final config = DeviceConfigModel.initialDefault();
      final json = config.toJson();

      expect(json['temp_max'], equals(38.0));
      expect(json['temp_min'], equals(10.0));
      expect(json['humi_max'], equals(90.0));
      expect(json['wind_max'], equals(15.0));
      expect(json['rain_max'], equals(30.0));
      expect(json['auto_warning'], isTrue);
      expect(json['buzzer'], isTrue);

      final fromJson = DeviceConfigModel.fromJson(json);
      expect(fromJson.tempMax, equals(38.0));
      expect(fromJson.windMax, equals(15.0));
    });
  });

  group('SettingsScreen Widget Tests', () {
    testWidgets('renders station dropdown, 3 command buttons, config fields and save button', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Dropdown chọn trạm
      expect(find.text('Trạm quan trắc'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

      // 2. Mục 1: Command với 3 nút bấm
      expect(find.text('Command'), findsOneWidget);
      expect(find.text('Bật LED'), findsOneWidget);
      expect(find.text('Buzzer'), findsOneWidget);
      expect(find.text('Reset'), findsOneWidget);

      // 3. Mục 2: Config Alert với các ô nhập liệu & Auto Alert
      expect(find.text('Config Alert'), findsOneWidget);
      expect(find.text('Ngưỡng nhiệt max'), findsOneWidget);
      expect(find.text('Ngưỡng nhiệt min'), findsOneWidget);
      expect(find.text('Ngưỡng độ ẩm'), findsOneWidget);
      expect(find.text('Ngưỡng gió'), findsOneWidget);
      expect(find.text('Ngưỡng độ mưa'), findsOneWidget);
      expect(find.text('Auto Alert'), findsOneWidget);
      expect(find.text('Kích hoạt còi Buzzer'), findsNothing);

      // 4. Nút Lưu Cấu Hình
      expect(find.text('Lưu Cấu Hình'), findsOneWidget);
    });
  });

  group('P06 Operation Lifecycle & Reconcile Tests', () {
    test('DeviceCommandNotifier distinguishes published vs applied and reconciles', () async {
      final repo = _FakeDeviceRepo();
      final container = ProviderContainer(
        overrides: [deviceRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final ok = await container
          .read(deviceCommandProvider.notifier)
          .sendInstantCommand('buzzer', labelVi: 'Buzzer');
      expect(ok, isTrue);
      expect(
        container.read(deviceCommandProvider).operationStatus,
        OperationLifecycleStatus.published,
      );

      repo.nextOperationStatus = OperationLifecycleStatus.applied;
      await container.read(deviceCommandProvider.notifier).reconcileActiveOperation();
      expect(
        container.read(deviceCommandProvider).operationStatus,
        OperationLifecycleStatus.applied,
      );
    });

    test('DeviceConfigNotifier tracks desiredVersion and reconciles reportedVersion', () async {
      final repo = _FakeDeviceRepo();
      final container = ProviderContainer(
        overrides: [deviceRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      final ok = await container.read(deviceConfigProvider.notifier).saveConfig();
      expect(ok, isTrue);
      expect(container.read(deviceConfigProvider).desiredVersion, 1);
      expect(container.read(deviceConfigProvider).reportedVersion, 0);
      expect(
        container.read(deviceConfigProvider).operationStatus,
        OperationLifecycleStatus.published,
      );

      repo.reportedVersion = 1;
      repo.nextOperationStatus = OperationLifecycleStatus.applied;
      await container.read(deviceConfigProvider.notifier).reconcileActiveConfig();
      expect(container.read(deviceConfigProvider).reportedVersion, 1);
      expect(
        container.read(deviceConfigProvider).operationStatus,
        OperationLifecycleStatus.applied,
      );
    });

    testWidgets('SettingsScreen loads station state on open and syncs TextEditingControllers', (tester) async {
      final repo = _FakeDeviceRepo(
        initialDesiredConfig: const DeviceConfigModel(
          tempMax: 41.5,
          tempMin: 12.5,
          humiMax: 85.0,
          windMax: 18.0,
          rainMax: 35.0,
          autoWarning: true,
          buzzer: true,
        ),
        desiredVersion: 3,
        reportedVersion: 2,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [deviceRepositoryProvider.overrideWithValue(repo)],
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('41.5'), findsOneWidget);
      expect(find.text('12.5'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Phiên bản: desired v3 · reported v2'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Phiên bản: desired v3 · reported v2'), findsOneWidget);
    });
  });
}

class _FakeDeviceRepo implements DeviceRepository {
  OperationLifecycleStatus nextOperationStatus = OperationLifecycleStatus.applied;
  DeviceConfigModel initialDesiredConfig;
  int desiredVersion;
  int reportedVersion;

  _FakeDeviceRepo({
    DeviceConfigModel? initialDesiredConfig,
    this.desiredVersion = 0,
    this.reportedVersion = 0,
  }) : initialDesiredConfig = initialDesiredConfig ?? DeviceConfigModel.initialDefault();

  @override
  Future<bool> sendCommand({
    required String deviceId,
    required DeviceCommandModel command,
  }) async =>
      true;

  @override
  Future<bool> updateConfig({
    required String deviceId,
    required DeviceConfigModel config,
  }) async =>
      true;

  @override
  Future<DeviceOperationResult> sendCommandOperation({
    required String deviceId,
    required DeviceCommandModel command,
    String? requestId,
  }) async {
    return DeviceOperationResult(
      operationId: requestId ?? 'cmd-1',
      status: OperationLifecycleStatus.published,
    );
  }

  @override
  Future<DeviceOperationResult> updateConfigOperation({
    required String deviceId,
    required DeviceConfigModel config,
    int? expectedVersion,
    String? requestId,
  }) async {
    desiredVersion++;
    return DeviceOperationResult(
      operationId: requestId ?? 'cfg-1',
      status: OperationLifecycleStatus.published,
      desiredVersion: desiredVersion,
    );
  }

  @override
  Future<StationStateSnapshot> getStationState(String deviceId) async {
    return StationStateSnapshot(
      deviceId: deviceId,
      desiredVersion: desiredVersion,
      desiredConfig: initialDesiredConfig,
      reportedVersion: reportedVersion,
    );
  }

  @override
  Future<DeviceOperationResult> getOperationStatus({
    required String deviceId,
    required String operationId,
  }) async {
    return DeviceOperationResult(
      operationId: operationId,
      status: nextOperationStatus,
    );
  }
}
