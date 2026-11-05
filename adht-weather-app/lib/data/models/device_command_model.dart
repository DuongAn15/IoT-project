/// Model lệnh gửi điều khiển phần cứng trạm ESP32 qua Backend Gateway
class DeviceCommandModel {
  final String cmd;
  final String? arg;

  const DeviceCommandModel({
    required this.cmd,
    this.arg,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'cmd': cmd,
    };
    if (arg != null && arg!.isNotEmpty) {
      map['arg'] = arg;
    }
    return map;
  }

  factory DeviceCommandModel.fromJson(Map<String, dynamic> json) {
    return DeviceCommandModel(
      cmd: json['cmd'] as String,
      arg: json['arg'] as String?,
    );
  }
}
