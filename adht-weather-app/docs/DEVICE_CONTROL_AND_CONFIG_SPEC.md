# 📡 ĐẶC TẢ GIAO DIỆN ĐIỀU KHIỂN & CẤU HÌNH THIẾT BỊ
## (ADHT Weather Station - Device Control & Configuration Specification)

> **Dành cho**: Đội ngũ phát triển Ứng dụng Di động (**Flutter Mobile App**) & Máy chủ (**Backend Gateway**).  
> **Phiên bản tài liệu**: 1.0.0 (Chuẩn hóa toàn diện hệ thống).  
> **Trạng thái**: Đã đối chiếu và kiểm chứng 100% khớp với Firmware ESP32 và Backend NestJS.

---

## 1. TỔNG QUAN KIẾN TRÚC & LUỒNG TRUYỀN DỮ LIỆU

Hệ thống hoạt động theo mô hình **Single Backend Gateway**. Ứng dụng Flutter **không gửi trực tiếp vào Broker MQTT hay chip ESP32**, mà gọi thông qua REST API của Backend. Backend sẽ kiểm tra quyền hạn và phát lệnh xuống Broker để chuyển tới ESP32 tương ứng.

```text
┌─────────────────────────┐          HTTP REST API          ┌─────────────────────────┐
│   FLUTTER MOBILE APP    │ ──────────────────────────────► │  NESTJS BACKEND GATEWAY │
│   (Giao diện người dùng)│                                 │   (Cửa ngõ trung gian)  │
└─────────────────────────┘                                 └─────────────────────────┘
                                                                         │
                                                                   MQTTS TLS 8883
                                                                   (QoS 1 Đảm bảo)
                                                                         ▼
┌─────────────────────────┐         MQTTS Subscribe         ┌─────────────────────────┐
│   ESP32 WEATHER STATION │ ◄────────────────────────────── │       EMQX CLOUD        │
│    (Trạm quan trắc thật)│                                 │      (MQTT Broker)      │
└─────────────────────────┘                                 └─────────────────────────┘
```

---

## 2. PHẦN 1: ĐẶC TẢ LỆNH ĐIỀU KHIỂN TỨC THỜI (`COMMAND`)

### 2.1. Mục đích
Dùng khi người dùng bấm nút trên App để **tác động ngay lập tức** lên linh kiện phần cứng tại trạm (ví dụ: kích hoạt còi hú kiểm tra, đảo trạng thái đèn LED, khởi động lại trạm vi điều khiển).

### 2.2. Hợp đồng REST API (App gọi Backend)
* **Phương thức**: `POST`
* **Đường dẫn**: `/api/devices/{device_id}/command`
  * Ví dụ: `http://192.168.1.100:8000/api/devices/adht_weather_01/command`
* **Headers**: `Content-Type: application/json`
* **Body Request**:
  ```json
  {
    "cmd": "buzzer",
    "arg": "500"
  }
  ```

### 2.3. Hợp đồng MQTT (Backend phát xuống ESP32)
* **Topic**: `adht/weather/{device_id}/command` *(hoặc topic chung `adht/weather/command`)*
* **Mức QoS**: `1` (Đảm bảo gói tin đến được trạm ít nhất một lần)
* **Payload**: Định dạng JSON tương tự Body Request.

### 2.4. Danh mục các Lệnh được ESP32 hỗ trợ

| Lệnh (`cmd`) | Tham số (`arg`) | Hành vi phần cứng ESP32 | Giao diện đề xuất trên Mobile App |
| :--- | :--- | :--- | :--- |
| `"buzzer"` | `"500"` *(số mili-giây kêu, kiểu chuỗi)* | Xuất mức `HIGH` ra chân **GPIO 2** trong khoảng thời gian `arg` ms rồi tự ngắt về `LOW`. Mặc định 300ms nếu `arg` rỗng. | **Nút bấm icon Còi**: *"🔔 Hú còi kiểm tra"* (Gửi `"arg": "500"`) |
| `"led"` | `""` *(để trống hoặc không truyền)* | Đảo trạng thái logic của chân **GPIO 33**: Đang Tắt ➔ Bật, Đang Bật ➔ Tắt. | **Nút bấm / Công tắc**: *"💡 Đèn LED kiểm tra"* |
| `"reset"` | `""` *(để trống)* | Gọi hàm `ESP.restart()`, khởi động lại hoàn toàn chip vi điều khiển ESP32. | **Nút bấm màu đỏ**: *"🔄 Khởi động lại trạm"* (Nên bật hộp thoại xác nhận trước khi gửi) |

---

## 3. PHẦN 2: ĐẶC TẢ CẤU HÌNH NGƯỠNG CẢNH BÁO (`CONFIG`)

### 3.1. Mục đích
Cho phép người dùng tùy chỉnh các ngưỡng thời tiết nguy hiểm từ xa. Khi ESP32 nhận được bản tin này, **nó sẽ lưu vĩnh viễn vào bộ nhớ Flash NVS (`Preferences`)**. Khi mất điện hoặc khởi động lại, cấu hình này vẫn được bảo toàn nguyên vẹn.

### 3.2. Hợp đồng REST API (App gọi Backend)
* **Phương thức**: `PUT`
* **Đường dẫn**: `/api/devices/{device_id}/config`
  * Ví dụ: `http://192.168.1.100:8000/api/devices/adht_weather_01/config`
* **Headers**: `Content-Type: application/json`
* **Body Request**:
  ```json
  {
    "temp_max": 38.0,
    "temp_min": 10.0,
    "humi_max": 90.0,
    "wind_max": 15.0,
    "rain_max": 50.0,
    "auto_warning": true,
    "buzzer": true
  }
  ```

### 3.3. Hợp đồng MQTT (Backend phát xuống ESP32)
* **Topic**: `adht/weather/{device_id}/config` *(hoặc topic chung `adht/weather/config`)*
* **Mức QoS**: `1`
* **Payload**: Định dạng JSON chứa cấu hình ngưỡng mới.

### 3.4. Danh mục các Tham số Cấu hình chi tiết

| Tên trường (Key) | Kiểu | Mặc định | Đơn vị | Ý nghĩa nghiệp vụ trên ESP32 | Gợi ý Widget trên App |
| :--- | :---: | :---: | :---: | :--- | :--- |
| `temp_max` | `double` | `38.0` | **°C** | Báo động khi nhiệt độ đo được $\ge$ ngưỡng này (Nắng nóng gay gắt). | Slider / Number Input (`30.0` – `50.0 °C`) |
| `temp_min` | `double` | `10.0` | **°C** | Báo động khi nhiệt độ đo được $\le$ ngưỡng này (Rét hại / Không khí lạnh). | Slider / Number Input (`0.0` – `20.0 °C`) |
| `humi_max` | `double` | `90.0` | **%** | Cảnh báo độ ẩm quá cao (Nồm ẩm, nguy cơ đọng sương hỏng linh kiện). | Slider (`70%` – `100%`) |
| `wind_max` | `double` | `15.0` | **m/s** | Cảnh báo gió giật mạnh cấp nguy hiểm (15 m/s tương đương gió giật Cấp 7). | Slider / Number Input (`5.0` – `30.0 m/s`) |
| `rain_max` | `double` | `50.0` | **mm/h** | Cảnh báo mưa xối xả (50 mm/h là ngưỡng mưa rất to, nguy cơ ngập úng). | Slider / Number Input (`10.0` – `100.0 mm/h`) |
| `auto_warning` | `bool` | `true` | - | Bật/Tắt chế độ tự động so sánh số đo cảm biến với ngưỡng để kích hoạt còi/LED. | **Switch (Công tắc)**: *"Tự động kích hoạt cảnh báo"* |
| `buzzer` | `bool` | `true` | - | Cho phép còi hú vật lý tại trạm kêu khi có cảnh báo (Nếu tắt, chỉ cảnh báo qua màn hình OLED). | **Switch (Công tắc)**: *"Cho phép còi Buzzer kêu"* |

---

## 4. BẰNG CHỨNG ĐỒNG BỘ MÃ NGUỒN (CODEBASE TRACEABILITY)

Tất cả các định dạng trên đã được đối chiếu chính xác tới từng dòng code trong dự án:

```text
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ 1. FIRMWARE ESP32                                                                           │
│   • mqtt_manager.cpp (Dòng 118-125): Đọc doc["cmd"] và doc["arg"]                           │
│   • mqtt_manager.cpp (Dòng 128-142): Đọc doc["temp_max"], doc["wind_max"], doc["buzzer"]... │
│   • main.cpp (Dòng 22-34): Xử lý if (cmd == "buzzer" | "led" | "reset")                     │
│   • storage_manager.cpp (Dòng 21-29): prefs.putFloat() lưu thẳng vào NVS Flash              │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│ 2. BACKEND NESTJS                                                                           │
│   • devices/dto/send-command.dto.ts: Khai báo class SendCommandDto { cmd, arg }             │
│   • devices/dto/update-config.dto.ts: Khai báo class UpdateConfigDto (7 trường dữ liệu)     │
│   • devices/devices.controller.ts: Cung cấp POST /:id/command và PUT /:id/config            │
├─────────────────────────────────────────────────────────────────────────────────────────────┤
│ 3. TRÌNH MÔ PHỎNG (tools/simulate_nodes.py)                                                 │
│   • Dòng 265-278: Nhận topic "command", parse cmd, arg và thực thi phản hồi                 │
│   • Dòng 280-292: Nhận topic "config", cập nhật bộ nhớ NVS giả lập                          │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 5. HƯỚNG DẪN CODE TRÊN FLUTTER APP (DART / DIO)

Dưới đây là mã nguồn mẫu sẵn sàng để đội ngũ Flutter tích hợp vào `adht-weather-app`:

### 5.1. Data Models (`lib/data/models/device_control_model.dart`)

```dart
/// Model gửi lệnh điều khiển xuống trạm
class DeviceCommandRequest {
  final String cmd;
  final String arg;

  DeviceCommandRequest({required this.cmd, this.arg = ''});

  Map<String, dynamic> toJson() => {
    'cmd': cmd,
    'arg': arg,
  };
}

/// Model cấu hình ngưỡng cảnh báo
class DeviceConfigModel {
  final double tempMax;
  final double tempMin;
  final double humiMax;
  final double windMax;
  final double rainMax;
  final bool autoWarning;
  final bool buzzerEnabled;

  DeviceConfigModel({
    this.tempMax = 38.0,
    this.tempMin = 10.0,
    this.humiMax = 90.0,
    this.windMax = 15.0,
    this.rainMax = 50.0,
    this.autoWarning = true,
    this.buzzerEnabled = true,
  });

  Map<String, dynamic> toJson() => {
    'temp_max': tempMax,
    'temp_min': tempMin,
    'humi_max': humiMax,
    'wind_max': windMax,
    'rain_max': rainMax,
    'auto_warning': autoWarning,
    'buzzer': buzzerEnabled,
  };

  factory DeviceConfigModel.fromJson(Map<String, dynamic> json) => DeviceConfigModel(
    tempMax: (json['temp_max'] as num?)?.toDouble() ?? 38.0,
    tempMin: (json['temp_min'] as num?)?.toDouble() ?? 10.0,
    humiMax: (json['humi_max'] as num?)?.toDouble() ?? 90.0,
    windMax: (json['wind_max'] as num?)?.toDouble() ?? 15.0,
    rainMax: (json['rain_max'] as num?)?.toDouble() ?? 50.0,
    autoWarning: json['auto_warning'] as bool? ?? true,
    buzzerEnabled: json['buzzer'] as bool? ?? true,
  );
}
```

### 5.2. API Client Service (`lib/data/services/device_api_service.dart`)

```dart
import 'package:dio/dio.dart';
import '../models/device_control_model.dart';

class DeviceApiService {
  final Dio dio;
  final String baseUrl;

  DeviceApiService(this.dio, {required this.baseUrl});

  /// Gửi lệnh điều khiển ngoại vi (buzzer, led, reset)
  Future<bool> sendCommand({
    required String deviceId,
    required String cmd,
    String arg = '',
  }) async {
    try {
      final req = DeviceCommandRequest(cmd: cmd, arg: arg);
      final res = await dio.post('$baseUrl/devices/$deviceId/command', data: req.toJson());
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Cập nhật ngưỡng cảnh báo vào NVS Flash
  Future<bool> updateConfig({
    required String deviceId,
    required DeviceConfigModel config,
  }) async {
    try {
      final res = await dio.put('$baseUrl/devices/$deviceId/config', data: config.toJson());
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
```

### 5.3. Gợi ý Widget Giao Diện trong `SettingsScreen`

```dart
// 1. Thẻ Điều Khiển Thiết Bị Nhanh
Card(
  child: Column(
    children: [
      ListTile(
        leading: const Icon(Icons.volume_up_rounded, color: Colors.orange),
        title: const Text('Kiểm tra Còi Buzzer'),
        subtitle: const Text('Hú còi 500ms để kiểm tra loa trạm'),
        trailing: ElevatedButton(
          onPressed: () => apiService.sendCommand(deviceId: 'adht_weather_01', cmd: 'buzzer', arg: '500'),
          child: const Text('Kích hoạt'),
        ),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.lightbulb_outline_rounded, color: Colors.amber),
        title: const Text('Đèn LED Báo Hiệu'),
        subtitle: const Text('Đảo trạng thái LED trạng thái trạm'),
        trailing: ElevatedButton(
          onPressed: () => apiService.sendCommand(deviceId: 'adht_weather_01', cmd: 'led'),
          child: const Text('Đổi LED'),
        ),
      ),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.restart_alt_rounded, color: Colors.red),
        title: const Text('Khởi Động Lại Trạm (Reboot)'),
        subtitle: const Text('Khởi động lại chip ESP32 từ xa'),
        trailing: OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => _confirmAndRestart(context),
          child: const Text('Reboot'),
        ),
      ),
    ],
  ),
);

// 2. Thẻ Cài Đặt Ngưỡng Cảnh Báo
Card(
  child: Column(
    children: [
      SwitchListTile(
        title: const Text('Tự động cảnh báo'),
        subtitle: const Text('Kích hoạt báo động khi chạm ngưỡng nguy hiểm'),
        value: currentConfig.autoWarning,
        onChanged: (val) => _saveConfig(currentConfig.copyWith(autoWarning: val)),
      ),
      SwitchListTile(
        title: const Text('Cho phép hú còi Buzzer'),
        subtitle: const Text('Bật âm thanh cảnh báo tại chỗ ở trạm'),
        value: currentConfig.buzzerEnabled,
        onChanged: (val) => _saveConfig(currentConfig.copyWith(buzzerEnabled: val)),
      ),
      // Slider nhiệt độ tối đa
      ListTile(
        title: Text('Ngưỡng nhiệt độ tối đa: ${currentConfig.tempMax}°C'),
        subtitle: Slider(
          value: currentConfig.tempMax,
          min: 30.0,
          max: 50.0,
          divisions: 20,
          label: '${currentConfig.tempMax}°C',
          onChanged: (val) => setState(() => currentConfig.tempMax = val),
          onChangeEnd: (val) => _saveConfig(currentConfig),
        ),
      ),
      // Slider gió giật tối đa
      ListTile(
        title: Text('Ngưỡng gió bão nguy hiểm: ${currentConfig.windMax} m/s'),
        subtitle: Slider(
          value: currentConfig.windMax,
          min: 5.0,
          max: 30.0,
          divisions: 25,
          label: '${currentConfig.windMax} m/s',
          onChanged: (val) => setState(() => currentConfig.windMax = val),
          onChangeEnd: (val) => _saveConfig(currentConfig),
        ),
      ),
    ],
  ),
);
```

---

## 6. TỔNG KẾT BẢNG MAPPING NHANH (CHEATSHEET)

| Nghiệp vụ | Endpoint Backend | MQTT Topic tương ứng | JSON Key gửi đi |
| :--- | :--- | :--- | :--- |
| **Kích hoạt còi** | `POST /api/devices/{id}/command` | `adht/weather/{id}/command` | `{"cmd": "buzzer", "arg": "500"}` |
| **Đổi đèn LED** | `POST /api/devices/{id}/command` | `adht/weather/{id}/command` | `{"cmd": "led", "arg": ""}` |
| **Reboot trạm** | `POST /api/devices/{id}/command` | `adht/weather/{id}/command` | `{"cmd": "reset", "arg": ""}` |
| **Lưu ngưỡng** | `PUT /api/devices/{id}/config` | `adht/weather/{id}/config` | `{"temp_max": 38.0, "temp_min": 10.0, "humi_max": 90.0, "wind_max": 15.0, "rain_max": 50.0, "auto_warning": true, "buzzer": true}` |
