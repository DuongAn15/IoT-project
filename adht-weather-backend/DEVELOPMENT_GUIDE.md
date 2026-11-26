# 📘 SỔ TAY KỸ THUẬT: BỘ KHUNG (SCAFFOLD) NESTJS BACKEND GATEWAY

> **Dành cho**: Thành viên đội ngũ phụ trách hiện thực hóa Backend (NestJS).

Chào bạn! Toàn bộ thư mục này là **bộ khung kiến trúc (Scaffold / Skeleton)** đã được dựng sẵn chuẩn mực theo NestJS 10 (TypeScript).

Mục tiêu của bộ khung này là giúp bạn:

1. **Không phải mất thời gian setup từ đầu**: Đã có sẵn cấu trúc Module, Controller, Service, DTO, Swagger UI, CORS, Dockerfile.
2. **Nắm rõ bản hợp đồng giao tiếp (API Contract)** giữa ESP32 ➔ Broker ➔ Backend ➔ Flutter App.
3. **Tự do hiện thực hóa logic theo cách của bạn** tại các vị trí đánh dấu `// TODO`.

---

## 1. Bản Đồ Bộ Khung (Architecture Map)

```text
src/
├── main.ts                      # Đã cấu hình CORS, Swagger UI (/docs), Prefix (/api), ValidationPipe
├── app.module.ts                # Đã import sẵn 7 modules con
├── config/                      # Cấu hình biến môi trường từ .env
└── modules/
    ├── mqtt/                    # 📌 [TODO] MqttService: Kết nối Broker MQTTS 8883, subscribe & publish
    ├── database/                # 📌 [TODO] SupabaseService: Ghi PostgreSQL & thuật toán Downsampling
    ├── notifications/           # 📌 [TODO] NotificationsService: Kiểm tra ngưỡng & gọi Firebase FCM Admin
    ├── websocket/               # 📌 [TODO] TelemetryGateway: Phát số đo tức thời mỗi 5s qua WebSocket
    ├── telemetry/               # 📌 [TODO] TelemetryController: Endpoint POST /api/telemetry (Webhook)
    ├── weather/                 # 📌 [TODO] WeatherController: GET latest và history
    └── devices/                 # 📌 [TODO] DevicesController: POST command, PUT config
```

---

## 2. Danh Sách Nhiệm Vụ (Developer TODO Checklist)

### 📌 Nhiệm vụ 1: Kết nối MQTT (`src/modules/mqtt/mqtt.service.ts`)

- [X] Dùng thư viện `mqtt` kết nối tới Broker EMQX Cloud (thông tin trong `.env`).
- [X] Subscribe topic cảm biến: `adht/weather/+/telemetry` và trạng thái `adht/weather/status`.
- [X] Khi có tin nhắn đến:
  - Gọi `SupabaseService.saveTelemetry(payload)` để lưu DB.
  - Gọi `NotificationsService.checkAndAlert(payload)` để kiểm tra giông bão.
  - Gọi `TelemetryGateway.broadcastTelemetry(payload)` để đẩy lên màn hình App/Web.
- [X] Hàm `publishCommand()`: Phát JSON xuống topic `adht/weather/{deviceId}/command`.
- [X] Hàm `publishConfig()`: Phát JSON xuống topic `adht/weather/{deviceId}/config`.

### 📌 Nhiệm vụ 2: Lưu trữ Database & Downsampling (`src/modules/database/supabase.service.ts`)

- [X] Khởi tạo client Supabase (`@supabase/supabase-js`) từ `SUPABASE_URL` và `SUPABASE_SERVICE_ROLE_KEY`.
- [X] Hàm `saveTelemetry()`: Insert bản ghi vào bảng `weather_logs`.
- [X] Hàm `getHistory(deviceId, range)`:
  - Do ESP32 gửi dữ liệu **5 giây/lần** (17.280 bản ghi/ngày), điện thoại di động không thể render hết hàng vạn điểm này.
  - Viết thuật toán gộp nhóm (Downsampling) tính trung bình (Nhiệt độ, Độ ẩm, Gió) theo các mốc `1h`, `6h`, `24h`, `3d`, `7d` trước khi trả về.

#### Cách `getHistory(deviceId, range)` gộp điểm lịch sử

Hàm lọc log của một thiết bị theo `device_id`, trong khoảng từ **hiện tại trừ `range` đến hiện tại**. Backend đọc nhiều trang từ Supabase rồi gộp log thành các khoảng nhỏ (bucket), không trả toàn bộ log thô.

| `range` | Khoảng dữ liệu  | Gộp mỗi | Số điểm dự kiến khi đủ dữ liệu |
| --------- | ------------------ | --------- | --------------------------------------- |
| `1h`    | 1 giờ gần nhất  | 1 phút   | 60                                      |
| `6h`    | 6 giờ gần nhất  | 5 phút   | 6 × 12 = 72                            |
| `24h`   | 24 giờ gần nhất | 10 phút  | 24 × 6 = 144                           |
| `3d`    | 3 ngày gần nhất | 30 phút  | 3 × 24 × 2 = 144                      |
| `7d`    | 7 ngày gần nhất | 1 giờ    | 7 × 24 = 168                           |

- Ví dụ `6h`: các log trong cùng một khoảng 5 phút được lấy trung bình thành một điểm; nếu thiết bị gửi đều mỗi 5 giây thì mỗi khoảng thường có 60 log.
- Mỗi điểm chứa trung bình `temp`, `humi`, `rain_rate`, `wind_speed`. Trung bình `rain_rate` vẫn là cường độ mưa (mm/giờ), không phải tổng lượng mưa (mm).
- Bucket bắt đầu từ đầu khoảng truy vấn, không nhất thiết trùng mốc phút/giờ trên đồng hồ. `recorded_at` của điểm là thời điểm bắt đầu bucket; kết quả sắp từ cũ đến mới.
- Bucket không có log sẽ không tạo điểm, không tự chèn số 0; vì vậy số điểm thực tế có thể ít hơn bảng trên.
- Code hiện tại lấy cả mốc kết thúc (`created_at <= end`): nếu có log đúng tại `end`, có thể xuất hiện thêm một điểm biên so với số dự kiến.

### 📌 Nhiệm vụ 3: Cảnh báo sớm thiên tai (`src/modules/notifications/notifications.service.ts`)

- [X] Khởi tạo Firebase Admin SDK từ file `serviceAccountKey.json`.
- [X] Hàm `checkAndAlert()`: So sánh `temp >= 38°C`, `wind_speed >= 15 m/s`, `rain_rate >= 30 mm/h`.
- [X] Hàm `sendPushNotification()`: Gửi tin nhắn FCM tới Topic `adht_weather_alerts`. (Lưu ý đặt cooldown 5 phút để tránh spam chuông điện thoại).
- [X] Hàm `registerToken()`: Đăng ký token từ Mobile App gửi lên vào Topic.

### 📌 Nhiệm vụ 4: Truyền dữ liệu thời gian thực (`src/modules/websocket/telemetry.gateway.ts`)

- [X] Gateway Socket.IO lắng nghe tại path `/ws/telemetry` trên cùng cổng HTTP của backend.
- [X] Hàm `broadcastTelemetry(data)`: Phát sự kiện `telemetry` chứa số đo hợp lệ tới tất cả client đang kết nối ngay khi nhận từ MQTT/HTTP. Chu kỳ khoảng 5 giây phụ thuộc phía gửi, không có timer phát lại dữ liệu cũ.
- [X] Hàm `broadcastStatus(data)`: Phát sự kiện `status` khi được gọi bởi luồng nhận trạng thái; không tự suy luận trạng thái offline.

### Forecast — ngoài phạm vi hệ thống

Forecast tạm hoãn để phát triển sau. Giữ source/spec hiện có; route/service/config được comment out và toàn bộ forecast tests dùng `test.skip()` để không chạy mặc định. Không expose endpoint hoặc trả `success` giả trong giai đoạn này. Khi feature được duyệt lại, cần khôi phục config/route/service và bỏ skip sau khi contract cùng provider được xác nhận.

---

## 3. Bản Hợp Đồng Dữ Liệu (Payload Contracts)

### Bản tin Telemetry từ ESP32 gửi lên Broker:

```json
{
  "device_id": "adht_weather_01",
  "timestamp": 1714567890,
  "temp": 31.4,
  "humi": 68.0,
  "heat_index": 36.2,
  "rain_rate": 0.0,
  "rain_total": 12.5,
  "wind_speed": 2.1,
  "wind_max": 4.5,
  "rssi": -58,
  "uptime": 3600
}
```

### Lưu ý về lượng mưa (`rain_total`)

- Backend yêu cầu `rain_total` là số không âm (mm), thống nhất với trường firmware publish tại `src/network/mqtt_manager.cpp` và công cụ mô phỏng.
- Firmware khởi tạo bộ đếm bằng 0, cộng dồn lượng mưa từ lúc thiết bị khởi động và reset khi khởi động lại. Bộ đếm không tự reset lúc 00:00.
- `rain_total` **không phải lượng mưa trong ngày** (`rain_daily`); không đổi tên hai trường cho nhau nếu chưa có thuật toán tính theo ngày, múi giờ và xử lý reboot.
- `rain_rate` là cường độ mưa (mm/giờ), không phải lượng mưa tích lũy (mm).
- Hợp đồng backend trước đây yêu cầu `rain_daily` nhưng firmware gửi `rain_total`, khiến telemetry bị từ chối. DTO HTTP/MQTT hiện dùng `rain_total`; payload chỉ có `rain_daily` không đáp ứng validation.
- Phần lưu Supabase hiện chỉ lưu các số đo được ánh xạ trong `SupabaseService` và chưa lưu `rain_total`. Nếu cần lưu/truy vấn lượng mưa tích lũy, phải bổ sung schema và mapping riêng; việc DTO nhận trường này không đồng nghĩa nó đã được lưu.

### Bản tin Lệnh từ Mobile App gửi xuống ESP32:

```json
{
  "cmd": "buzzer",
  "arg": "500"
}
```

---

## 4. Cách Chạy Thử Khung Ứng Dụng (Hỗ trợ cả Bun và NPM)

Bạn có thể dùng **Bun** hoặc **NPM** tùy ý:

```bash
cd adht-weather-backend

# 1. Cài đặt thư viện
bun install
# (hoặc: npm install)

# 2. Tạo .env từ template mẫu
cp .env.example .env

# 3. Khởi chạy ở chế độ Hot-reload
bun dev
# (hoặc: npm run start:dev)
```

- Mở trình duyệt xem toàn bộ khung API tại Swagger UI: `http://localhost:8000/docs`
- Mở terminal thứ 2 tại thư mục gốc dự án và chạy simulator trạm ảo:
  ```bash
  python3 tools/simulate_nodes.py
  ```
