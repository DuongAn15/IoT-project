# API Request & Response

Tài liệu phản ánh controller, DTO và service hiện tại của backend.

- Base URL mặc định: `http://localhost:8000/api` (có thể thay đổi qua cấu hình).
- Swagger: `http://localhost:8000/docs`.
- Request có body dùng `Content-Type: application/json`.
- Các timestamp dưới đây chỉ là ví dụ; response thực tế dùng thời điểm xử lý request.
- Supabase, dự báo và FCM vẫn là **stub**. Response thành công không đồng nghĩa dữ liệu đã được lưu hoặc thông báo đã được gửi thật.

## Danh sách API

| Method | Endpoint | Chức năng |
| --- | --- | --- |
| POST | `/api/telemetry` | Nhận số đo cảm biến |
| GET | `/api/weather/latest` | Lấy số đo mới nhất |
| GET | `/api/weather/history` | Lấy lịch sử số đo |
| GET | `/api/weather/forecast` | Lấy dự báo |
| POST | `/api/devices` | Thêm thiết bị vào Supabase |
| GET | `/api/devices` | Lấy tất cả thiết bị |
| GET | `/api/devices/:id` | Lấy thiết bị theo device_id |
| POST | `/api/devices/:id/command` | Gửi lệnh qua MQTT |
| PUT | `/api/devices/:id/config` | Gửi cấu hình qua MQTT |
| POST | `/api/notifications/register-token` | Đăng ký FCM token |

## Quản lý danh mục thiết bị

Ba API danh mục thiết bị đọc/ghi trực tiếp bảng `public.devices` trong Supabase,
không phải stub. Bảng cần có `device_id` (text, primary key), `name` (text, not null),
`mac` (text, not null, unique). Backend cần quyền đọc/ghi phù hợp với RLS;
không đưa service-role key vào app.

### Thêm thiết bị

`POST /api/devices`

```json
{
  "device_id": "adht_weather_02",
  "name": "Trạm 02 Ảo - Nắng Nóng",
  "mac": "02:00:00:00:00:02"
}
```

ID và tên được trim, không được rỗng. MAC gồm sáu cặp hex ngăn bằng dấu `:`,
được trim và chuẩn hóa thành chữ hoa.

Response HTTP 201:

```json
{
  "statusCode": 201,
  "data": {
    "device_id": "adht_weather_02",
    "name": "Trạm 02 Ảo - Nắng Nóng",
    "mac": "02:00:00:00:00:02"
  },
  "timestamp": "2026-11-17T00:00:00.000Z"
}
```

### Lấy danh sách và chi tiết

- `GET /api/devices`: HTTP 200, `data` là mảng thiết bị, sắp theo `device_id`;
  trả `[]` nếu chưa có thiết bị.
- `GET /api/devices/adht_weather_02`: HTTP 200, `data` là một thiết bị.
- HTTP 400: body không hợp lệ; 404: không tìm thấy ID; 409: trùng ID hoặc MAC;
  503: lỗi truy cập Supabase.

Các API này chưa có cơ chế xác thực/phân quyền, giống các API thiết bị hiện tại.
Cần bảo vệ endpoint thêm thiết bị trước khi mở cho người dùng không tin cậy.
Việc thêm thiết bị không tự đăng ký MQTT, cập nhật firmware hoặc sửa dữ liệu log cũ.

## 1. Nhận telemetry

### API

`POST /api/telemetry`

### Request mẫu

```json
{
  "device_id": "adht_weather_03",
  "temp": 24.4,
  "humi": 92.5,
  "rain_rate": 29.75,
  "rain_total": 9.5,
  "wind_speed": 4.4,
  "wind_max": 11.1,
  "rssi": -59,
  "uptime": 115
}
```

| Trường | Bắt buộc | Kiểu / giới hạn |
| --- | --- | --- |
| `device_id` | Có | String không rỗng |
| `temp` | Có | Number, từ -40 đến 80 °C |
| `humi` | Có | Number, từ 0 đến 100 % |
| `rain_rate` | Có | Number ≥ 0, mm/giờ |
| `rain_total` | Có | Number ≥ 0, mm tích lũy từ lúc thiết bị khởi động |
| `wind_speed` | Có | Number ≥ 0, m/s |
| `timestamp` | Không | Number, Unix timestamp |
| `heat_index` | Không | Number, nhiệt độ cảm nhận (°C) |
| `wind_max` | Không | Number, tốc độ gió lớn nhất (m/s) |
| `rssi` | Không | Number, cường độ Wi-Fi (dBm) |
| `uptime` | Không | Number, thời gian hoạt động (giây) |

Backend dùng `rain_total` thống nhất với firmware và simulator: lượng mưa tích lũy từ lúc khởi động, không phải lượng mưa trong ngày. Payload chỉ có `rain_daily` bị từ chối vì thiếu `rain_total`. Supabase hiện chưa lưu trường này; xem ghi chú trong `DEVELOPMENT_GUIDE.md`.

### Response hiện tại — HTTP 201

```json
{
  "statusCode": 201,
  "data": {
    "status": "success",
    "message": "Telemetry received (Stub)"
  },
  "timestamp": "2026-11-04T05:00:00.000Z"
}
```

Backend gọi stub lưu dữ liệu, stub kiểm tra cảnh báo và phát event Socket.IO `telemetry`.

## 2. Lấy số đo mới nhất

### API / Request mẫu

`GET /api/weather/latest?device_id=adht_weather_03`

Query `device_id` không bắt buộc. Không có request body.

### Response hiện tại — HTTP 200

```json
{
  "statusCode": 200,
  "data": null,
  "timestamp": "2026-11-04T05:00:00.000Z"
}
```

Truy vấn Supabase chưa triển khai, nên endpoint hiện chưa trả số đo MQTT vừa nhận.

## 3. Lấy lịch sử số đo

### API / Request mẫu

`GET /api/weather/history?device_id=adht_weather_03&range=24h`

| Query | Bắt buộc | Mặc định / giá trị |
| --- | --- | --- |
| `device_id` | Không | `adht_weather_01` |
| `range` | Không | Mặc định `24h`; cho phép `1h`, `6h`, `24h`, `3d`, `7d` |

### Response hiện tại — HTTP 200

```json
{
  "statusCode": 200,
  "data": {
    "device_id": "adht_weather_03",
    "range": "24h",
    "points_count": 0,
    "data": []
  },
  "timestamp": "2026-11-04T05:00:00.000Z"
}
```

Truy vấn lịch sử vẫn là stub; chưa có hợp đồng điểm dữ liệu thực tế để minh họa.

## 4. Lấy dự báo

### API / Request mẫu

`GET /api/weather/forecast?lat=10.8231&lon=106.6297`

Query `lat` (vĩ độ) và `lon` (kinh độ) đều không bắt buộc. Không có request body.

### Response hiện tại — HTTP 200

```json
{
  "statusCode": 200,
  "data": {
    "status": "success",
    "message": "TODO: Tích hợp OpenWeatherMap API",
    "coords": {
      "lat": 10.8231,
      "lon": 106.6297
    },
    "forecast_days": []
  },
  "timestamp": "2026-11-04T05:00:00.000Z"
}
```

Chưa tích hợp API dự báo thật.

## 5. Gửi lệnh điều khiển

### API

`POST /api/devices/adht_weather_03/command`

### Request mẫu

```json
{
  "cmd": "buzzer",
  "arg": "500"
}
```

- `cmd`: bắt buộc, string không rỗng.
- `arg`: không bắt buộc, string; dùng `"500"`, không dùng số `500`.
- Swagger liệt kê `buzzer`, `led`, `reboot`, `reset_rain`, nhưng DTO chưa giới hạn tập lệnh. Khả năng thực thi phụ thuộc firmware, không được đảm bảo chỉ bởi mô tả Swagger.

### Response khi publish thành công — HTTP 201

```json
{
  "statusCode": 201,
  "data": {
    "status": "success",
    "deviceId": "adht_weather_03",
    "command": {
      "cmd": "buzzer",
      "arg": "500"
    }
  },
  "timestamp": "2026-11-04T05:00:00.000Z"
}
```

MQTT topic đích: `adht/weather/adht_weather_03/command`.

`success` chỉ xác nhận broker nhận bản tin QoS 1, không xác nhận thiết bị đã thực thi. Nếu publish thất bại, `data.status` là `"failed"`, nhưng HTTP vẫn là `201` theo code hiện tại.

## 6. Cập nhật cấu hình

### API

`PUT /api/devices/adht_weather_03/config`

### Request mẫu

```json
{
  "temp_max": 38,
  "temp_min": 10,
  "humi_max": 90,
  "wind_max": 15,
  "rain_max": 30,
  "auto_warning": true,
  "buzzer": true
}
```

Tất cả trường đều không bắt buộc, có thể chỉ gửi trường cần thay đổi.

| Trường | Kiểu | Ý nghĩa |
| --- | --- | --- |
| `temp_max` | Number | Ngưỡng nhiệt độ tối đa (°C) |
| `temp_min` | Number | Ngưỡng nhiệt độ tối thiểu (°C) |
| `humi_max` | Number | Ngưỡng độ ẩm tối đa (%) |
| `wind_max` | Number | Ngưỡng tốc độ gió nguy hiểm (m/s) |
| `rain_max` | Number | Ngưỡng cường độ mưa (mm/giờ) |
| `auto_warning` | Boolean | Tự động báo còi khi vượt ngưỡng |
| `buzzer` | Boolean | Bật/tắt còi |

### Response khi publish thành công — HTTP 200

```json
{
  "statusCode": 200,
  "data": {
    "status": "success",
    "deviceId": "adht_weather_03",
    "config": {
      "temp_max": 38,
      "temp_min": 10,
      "humi_max": 90,
      "wind_max": 15,
      "rain_max": 30,
      "auto_warning": true,
      "buzzer": true
    }
  },
  "timestamp": "2026-11-04T05:00:00.000Z"
}
```

MQTT topic đích: `adht/weather/adht_weather_03/config`.

Thành công chỉ xác nhận broker nhận bản tin, không đảm bảo thiết bị đã áp dụng/lưu cấu hình. Nếu publish thất bại, `data.status` là `"failed"`, HTTP vẫn là `200`.

## 7. Đăng ký FCM token

### API

`POST /api/notifications/register-token`

### Request mẫu

```json
{
  "fcm_token": "example-fcm-token-for-testing",
  "device_name": "Samsung Galaxy S24"
}
```

- `fcm_token`: bắt buộc, string không rỗng; token trên chỉ để minh họa.
- `device_name`: không bắt buộc, string. Controller hiện chưa chuyển trường này xuống service.

### Response hiện tại — HTTP 201

```json
{
  "statusCode": 201,
  "data": {
    "status": "success",
    "message": "FCM Token registered (Stub)",
    "token": "example-fcm-tok..."
  },
  "timestamp": "2026-11-04T05:00:00.000Z"
}
```

Chưa đăng ký token hoặc gửi thông báo FCM thật.

## 8. Response lỗi validation

Ví dụ gửi telemetry với `rain_total: -1` và các trường còn lại hợp lệ:

```json
{
  "statusCode": 400,
  "timestamp": "2026-11-04T05:00:00.000Z",
  "path": "/api/telemetry",
  "error": {
    "message": [
      "rain_total must not be less than 0"
    ],
    "error": "Bad Request",
    "statusCode": 400
  }
}
```

Response lỗi không có wrapper `data`. Các trường body không thuộc DTO bị loại bỏ bởi validation; chúng không thay thế được trường bắt buộc bị thiếu.

## 9. Realtime Socket.IO và MQTT

### Kết nối Socket.IO

Socket.IO dùng cùng host/port HTTP và path `/ws/telemetry`, không có prefix `/api`. Đây không phải WebSocket thuần.

```ts
import { io } from 'socket.io-client';

const socket = io('http://localhost:8000', {
  path: '/ws/telemetry',
});

socket.on('telemetry', (data) => {
  // Nhận số đo cảm biến đã qua validation.
});

socket.on('status', (data) => {
  // Nhận JSON trạng thái chuyển tiếp từ MQTT.
});

socket.emit('ping', (response: string) => {
  // response là 'pong'.
});
```

### Event và payload

| Event | Chiều | Payload |
| --- | --- | --- |
| `telemetry` | Server → client | Cùng các trường của request telemetry, không có wrapper HTTP |
| `status` | Server → client | JSON object chuyển tiếp từ MQTT; chưa có DTO cố định |
| `ping` | Client → server | Không cần payload; nhận `"pong"` qua acknowledgement |

Payload mẫu cho event `telemetry`:

```json
{
  "device_id": "adht_weather_03",
  "temp": 24.4,
  "humi": 92.5,
  "rain_rate": 29.75,
  "rain_total": 9.5,
  "wind_speed": 4.4,
  "wind_max": 11.1,
  "rssi": -59,
  "uptime": 115
}
```

### MQTT topics

| Topic | Chiều nhìn từ backend | Payload |
| --- | --- | --- |
| `adht/weather/+/telemetry` | Subscribe | JSON theo DTO telemetry; `device_id` phải trùng ID trong topic |
| `adht/weather/status` | Subscribe | JSON object trạng thái, chưa có DTO cố định |
| `adht/weather/:id/command` | Publish | Body của API gửi lệnh |
| `adht/weather/:id/config` | Publish | Body của API cập nhật cấu hình |

Ví dụ topic telemetry: `adht/weather/adht_weather_03/telemetry` với payload ở trên. Bản tin MQTT không hợp lệ bị bỏ qua và ghi warning, không trả response HTTP.

## Ghi chú về HTTP status

Swagger hiện mô tả response POST là `200`, nhưng controller chưa đặt `@HttpCode(200)`, nên NestJS thực tế mặc định trả `201`. Các ví dụ trong tài liệu này dùng status theo code hiện tại.
