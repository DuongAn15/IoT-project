import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_monitoring/data/models/device_command_model.dart';
import 'package:weather_monitoring/data/models/device_config_model.dart';
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
}
