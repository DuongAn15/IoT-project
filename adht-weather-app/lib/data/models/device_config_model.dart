/// Model cấu hình ngưỡng cảnh báo phần cứng trạm ESP32 (lưu vào NVS Flash)
class DeviceConfigModel {
  final double? tempMax;
  final double? tempMin;
  final double? humiMax;
  final double? windMax;
  final double? rainMax;
  final bool? autoWarning;
  final bool? buzzer;

  const DeviceConfigModel({
    this.tempMax,
    this.tempMin,
    this.humiMax,
    this.windMax,
    this.rainMax,
    this.autoWarning,
    this.buzzer,
  });

  /// Giá trị mặc định chuẩn định dạng ban đầu cho form cấu hình
  factory DeviceConfigModel.initialDefault() {
    return const DeviceConfigModel(
      tempMax: 38.0,
      tempMin: 10.0,
      humiMax: 90.0,
      windMax: 15.0,
      rainMax: 30.0,
      autoWarning: true,
      buzzer: true,
    );
  }

  DeviceConfigModel copyWith({
    double? tempMax,
    double? tempMin,
    double? humiMax,
    double? windMax,
    double? rainMax,
    bool? autoWarning,
    bool? buzzer,
  }) {
    return DeviceConfigModel(
      tempMax: tempMax ?? this.tempMax,
      tempMin: tempMin ?? this.tempMin,
      humiMax: humiMax ?? this.humiMax,
      windMax: windMax ?? this.windMax,
      rainMax: rainMax ?? this.rainMax,
      autoWarning: autoWarning ?? this.autoWarning,
      buzzer: buzzer ?? this.buzzer,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (tempMax != null) map['temp_max'] = tempMax;
    if (tempMin != null) map['temp_min'] = tempMin;
    if (humiMax != null) map['humi_max'] = humiMax;
    if (windMax != null) map['wind_max'] = windMax;
    if (rainMax != null) map['rain_max'] = rainMax;
    if (autoWarning != null) map['auto_warning'] = autoWarning;
    if (buzzer != null) map['buzzer'] = buzzer;
    return map;
  }

  factory DeviceConfigModel.fromJson(Map<String, dynamic> json) {
    return DeviceConfigModel(
      tempMax: (json['temp_max'] as num?)?.toDouble(),
      tempMin: (json['temp_min'] as num?)?.toDouble(),
      humiMax: (json['humi_max'] as num?)?.toDouble(),
      windMax: (json['wind_max'] as num?)?.toDouble(),
      rainMax: (json['rain_max'] as num?)?.toDouble(),
      autoWarning: json['auto_warning'] as bool?,
      buzzer: json['buzzer'] as bool?,
    );
  }
}
