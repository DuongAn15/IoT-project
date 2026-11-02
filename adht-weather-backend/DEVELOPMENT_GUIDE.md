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
    ├── weather/                 # 📌 [TODO] WeatherController: GET latest, history, forecast
    └── devices/                 # 📌 [TODO] DevicesController: POST command, PUT config
```

---

## 2. Danh Sách Nhiệm Vụ (Developer TODO Checklist)

### 📌 Nhiệm vụ 1: Kết nối MQTT (`src/modules/mqtt/mqtt.service.ts`)
- [ ] Dùng thư viện `mqtt` kết nối tới Broker EMQX Cloud (thông tin trong `.env`).
- [ ] Subscribe topic cảm biến: `adht/weather/+/telemetry` và trạng thái `adht/weather/status`.
- [ ] Khi có tin nhắn đến:
  - Gọi `SupabaseService.saveTelemetry(payload)` để lưu DB.
  - Gọi `NotificationsService.checkAndAlert(payload)` để kiểm tra giông bão.
  - Gọi `TelemetryGateway.broadcastTelemetry(payload)` để đẩy lên màn hình App/Web.
- [ ] Hàm `publishCommand()`: Phát JSON xuống topic `adht/weather/{deviceId}/command`.
- [ ] Hàm `publishConfig()`: Phát JSON xuống topic `adht/weather/{deviceId}/config`.

### 📌 Nhiệm vụ 2: Lưu trữ Database & Downsampling (`src/modules/database/supabase.service.ts`)
- [ ] Khởi tạo client Supabase (`@supabase/supabase-js`) từ `SUPABASE_URL` và `SUPABASE_SERVICE_ROLE_KEY`.
- [ ] Hàm `saveTelemetry()`: Insert bản ghi vào bảng `weather_logs`.
- [ ] Hàm `getHistory(deviceId, range)`:
  - Do ESP32 gửi dữ liệu **5 giây/lần** (17.280 bản ghi/ngày), điện thoại di động không thể render hết hàng vạn điểm này.
  - Viết thuật toán gộp nhóm (Downsampling) tính trung bình (Nhiệt độ, Độ ẩm, Gió) theo các mốc `1h`, `6h`, `24h`, `3d`, `7d` trước khi trả về.

### 📌 Nhiệm vụ 3: Cảnh báo sớm thiên tai (`src/modules/notifications/notifications.service.ts`)
- [ ] Khởi tạo Firebase Admin SDK từ file `serviceAccountKey.json`.
- [ ] Hàm `checkAndAlert()`: So sánh `temp >= 38°C`, `wind_speed >= 15 m/s`, `rain_rate >= 30 mm/h`.
- [ ] Hàm `sendPushNotification()`: Gửi tin nhắn FCM tới Topic `adht_weather_alerts`. (Lưu ý đặt cooldown 5 phút để tránh spam chuông điện thoại).
- [ ] Hàm `registerToken()`: Đăng ký token từ Mobile App gửi lên vào Topic.

### 📌 Nhiệm vụ 4: Truyền dữ liệu thời gian thực (`src/modules/websocket/telemetry.gateway.ts`)
- [ ] Gateway đã lắng nghe tại path `/ws/telemetry`.
- [ ] Hàm `broadcastTelemetry(data)`: Gửi sự kiện `telemetry` chứa JSON số đo cảm biến mỗi 5s tới các client Flutter App / Web Dashboard đang kết nối.

### 📌 Nhiệm vụ 5: Tích hợp OpenWeatherMap (`src/modules/weather/weather.service.ts`)
- [ ] Dùng `axios` gọi OpenWeatherMap API để lấy dự báo thời tiết 3 ngày cho màn hình Forecast của Flutter App.

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
  "rain_daily": 12.5,
  "wind_speed": 2.1,
  "wind_max": 4.5,
  "rssi": -58,
  "uptime": 3600
}
```

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
