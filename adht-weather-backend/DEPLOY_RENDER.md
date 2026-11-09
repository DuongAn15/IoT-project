# 🚀 Deploy Backend lên Render (Free) + UptimeRobot

Backend chạy 24/7 trên Render. Backend **tự kết nối ra** EMQX (MQTT) và Supabase (HTTPS), nên không cần mở cổng hay cấu hình gì phía broker/database. App Flutter gọi vào URL public `https://<tên-service>.onrender.com`.

```
ESP32 / simulator ──MQTT──► EMQX Cloud ◄──MQTT (backend tự kết nối)── Render: NestJS ──HTTPS──► Supabase
                                                                          ▲      └──────────► Firebase FCM
                                     UptimeRobot ping /api/health 5'/lần ─┤
                                     Flutter app ── REST + Socket.IO ─────┘
```

Cấu hình service nằm trong [`render.yaml`](../render.yaml) ở gốc repo (Render Blueprint).

---

## 1. Chuẩn bị

- Tài khoản [Render](https://render.com) đăng nhập bằng GitHub.
- Render phải được cấp quyền đọc repo `DuongAn15/IoT-project`. Nếu bạn không phải chủ repo: nhờ chủ repo cài Render GitHub App cho repo này, hoặc chủ repo tự tạo Blueprint.
- Chuẩn bị sẵn các giá trị từ `adht-weather-backend/.env` (không commit file này).
- Chuyển file key Firebase sang base64 (để dán vào 1 ô env mà không bị lỗi xuống dòng):

  ```powershell
  # PowerShell (Windows): mã hóa base64 và copy vào clipboard
  cd adht-weather-backend
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("$PWD\adth-weather-firebase-firebase-adminsdk-fbsvc-edea67a10d.json")) | Set-Clipboard
  ```

  ```bash
  # Linux / macOS
  base64 -w0 adth-weather-firebase-firebase-adminsdk-*.json   # macOS: base64 -i <file>
  ```

## 2. Tạo service từ Blueprint

1. Render Dashboard → **New** → **Blueprint**.
2. Chọn repo `IoT-project` và branch muốn deploy (vd. `master` sau khi merge).
3. Render đọc `render.yaml` và hỏi các biến `sync: false`. Điền:

   | Biến | Giá trị |
   |---|---|
   | `MQTT_BROKER_HOST` | Hostname EMQX, **không** có `mqtts://` |
   | `MQTT_USERNAME`, `MQTT_PASSWORD` | Tài khoản MQTT trong EMQX (nên tạo riêng cho backend) |
   | `SUPABASE_URL` | `https://xxxx.supabase.co` |
   | `SUPABASE_SERVICE_ROLE_KEY` | Supabase → Project Settings → API → `service_role` |
   | `FIREBASE_CREDENTIALS_JSON` | Chuỗi base64 vừa copy ở bước 1 |
   | `OPENWEATHER_API_KEY` | Key OpenWeather |
   | `DEFAULT_LAT`, `DEFAULT_LON` | Tọa độ trạm (vd. Đà Nẵng `16.0544`, `108.2022`) |

4. **Apply** → Render build Docker image (lần đầu khoảng 3–5 phút).
5. Xem tab **Logs**, phải thấy:
   ```
   Firebase Admin messaging initialized
   Nest application successfully started
   Connected to MQTT broker
   Subscribed to adht/weather/+/telemetry and adht/weather/status
   ```

> ⚠️ Biến `sync: false` chỉ được hỏi **lần đầu** tạo Blueprint. Sau này thêm/sửa secret thì vào service → **Environment**.

## 3. Kiểm tra

Thay `<url>` bằng URL Render cấp (có thể có hậu tố nếu tên đã bị dùng, vd. `adht-weather-backend-abcd.onrender.com`):

```bash
curl https://<url>/api/health          # {"statusCode":200,"data":{"status":"ok","mqtt_connected":true,...}}
curl https://<url>/api/weather/latest  # bản ghi mới nhất từ Supabase
```

Swagger UI: `https://<url>/docs`.

## 4. Giữ service không ngủ bằng UptimeRobot

Render free sẽ ngủ sau ~15 phút không có request HTTP. Kết nối MQTT **không** được tính là traffic, nên khi ngủ backend sẽ ngừng lưu dữ liệu và không gửi cảnh báo FCM.

1. Đăng ký [UptimeRobot](https://uptimerobot.com) (free).
2. **Add New Monitor**:
   - Monitor Type: **HTTP(s)**
   - URL: `https://<url>/api/health`
   - Monitoring Interval: **5 minutes**
3. Lưu lại. UptimeRobot cũng email cho bạn khi backend sập.

`/api/health` không gọi Supabase/Firebase nên ping liên tục không tốn tài nguyên.

## 5. Trỏ app Flutter tới backend cloud

Sửa `adht-weather-app/lib/core/constants/api_constants.dart`:

```dart
static const String defaultBaseUrl = 'https://<url>/api';
```

WebSocket (Socket.IO): `wss://<url>` với path `/ws/telemetry`.

## 6. Lưu ý khi vận hành

- **Không chạy backend local cùng lúc với cloud bằng chung `MQTT_CLIENT_ID`**: broker sẽ đá một bên ra. Bản cloud dùng `adht_backend_cloud`. Kể cả khác client ID, cả hai bản đều ghi telemetry vào Supabase → **dữ liệu bị trùng**. Khi dev local nên dùng project Supabase/topic riêng, hoặc tạm suspend service trên Render.
- **Free plan**: 512 MB RAM, 0.1 CPU, 750 giờ/tháng (đủ 1 service chạy 24/7). Mỗi lần deploy lại sẽ mất kết nối MQTT khoảng 1–2 phút.
- **Auto deploy**: chỉ build lại khi có commit thay đổi trong `adht-weather-backend/**` trên branch đã nối.
- **Firmware chưa gửi đúng topic**: ESP32 thật đang publish `adht/weather/telemetry`, còn backend subscribe `adht/weather/+/telemetry` → số liệu từ trạm thật chưa vào backend (simulator thì vào được). Cần sửa topic trong `adht-weather-firmware/src/config.h`.

## 7. Xử lý sự cố

| Triệu chứng trong Logs | Nguyên nhân / cách sửa |
|---|---|
| `Unable to initialize Firebase Admin` | `FIREBASE_CREDENTIALS_JSON` sai: copy lại chuỗi base64, không có khoảng trắng thừa |
| `Missing Supabase configuration` | Thiếu `SUPABASE_URL` hoặc `SUPABASE_SERVICE_ROLE_KEY` |
| `Failed to save telemetry to Supabase` (lỗi RLS / 42501) | Đang dùng anon key thay vì service role key |
| `MQTT error: Not authorized` / `connack` | Sai user/pass MQTT hoặc EMQX chưa cấp quyền subscribe `adht/weather/#` |
| Health check fail, service restart liên tục | Xem log khởi động; app phải lắng nghe đúng `PORT` do Render cấp (đã xử lý trong `main.ts`) |
