# 🌦️ KẾ HOẠCH DỰ ÁN: TRẠM QUAN TRẮC THỜI TIẾT THÔNG MINH ADHT

> **Đơn vị phát triển**: Nhóm ADHT  
> **Mô hình Repository**: Monorepo (Quản lý tập trung toàn bộ Firmware và Mobile App trong 1 Repository duy nhất)  
> **Công nghệ lõi**: ESP32 (FreeRTOS) + HiveMQ Cloud (MQTT TLS) + Supabase (PostgreSQL REST API) + Flutter Mobile App  

---

## MỤC LỤC
1. [Cấu trúc Thư mục Dự án (Monorepo Structure)](#1-cấu-trúc-thư-mục-dự-án-monorepo-structure)
2. [Sơ đồ Kiến trúc Hệ thống](#2-sơ-đồ-kiến-trúc-hệ-thống)
3. [Đặc tả Phần cứng & Sơ đồ nối chân (Pinout)](#3-đặc-tả-phần-cứng--sơ-đồ-nối-chân-pinout)
4. [Đặc tả Giao thức Mạng & MQTT Topics](#4-đặc-tả-giao-thức-mạng--mqtt-topics)
5. [Đặc tả Cơ sở dữ liệu Supabase](#5-đặc-tả-cơ-sở-dữ-liệu-supabase)
6. [Đặc tả Ứng dụng Di động (Flutter Mobile App)](#6-đặc-tả-ứng-dụng-di-động-flutter-mobile-app)
7. [Lộ trình Triển khai Dự án (5 Tuần)](#7-lộ-trình-triển-khai-dự-án-5-tuần)
8. [Kế hoạch Kiểm thử & Đánh giá chất lượng (QA/QC)](#8-kế-hoạch-kiểm-thử--đánh-giá-chất-lượng-qaqc)
9. [Hướng dẫn Cài đặt & Vận hành Nhanh (Quickstart)](#9-hướng-dẫn-cài-đặt--vận-hành-nhanh-quickstart)

---

## 1. CẤU TRÚC THƯ MỤC DỰ ÁN (MONOREPO STRUCTURE)

Dự án được tổ chức theo mô hình **Monorepo** với 2 phân hệ độc lập: Phần cứng nhúng (`adht-weather-firmware`) và Ứng dụng di động (`adht-weather-app`).

```text
IoT-project/
├── adht-weather-firmware/               # Phân hệ Nhúng (ESP32 PlatformIO C++)
│   ├── platformio.ini                  # Cấu hình board esp32doit-devkit-v1, tốc độ nạp & thư viện
│   ├── include/                        # Header dùng chung
│   ├── lib/                            # Thư viện cục bộ (Adafruit GFX, SH110X, DHT, Kalman)
│   └── src/
│       ├── config.h                    # Cấu hình WiFi, HiveMQ Cloud, Supabase API Key & Pinout
│       ├── types.h                     # Cấu trúc dữ liệu WeatherData, SystemConfig, NetworkStatus
│       ├── main.cpp                    # Hàm setup(), khởi tạo và điều phối 4 Task FreeRTOS trên 2 Core
│       ├── sensors/
│       │   ├── sensor_manager.h        # Khai báo bộ đọc cảm biến
│       │   └── sensor_manager.cpp      # Đọc DHT11 (bộ lọc Kalman), ngắt đo xung Mưa và Gió
│       ├── network/
│       │   ├── wifi_manager.h/.cpp     # Quản lý kết nối WiFi và cơ chế tự động kết nối lại
│       │   ├── mqtt_manager.h/.cpp     # Client MQTT kết nối HiveMQ Cloud (TLS 8883), LWT, Pub/Sub
│       │   └── supabase_manager.h/.cpp # Client HTTPS POST gửi dữ liệu JSON vào Supabase REST API
│       ├── display/
│       │   ├── oled_manager.h          # Khai báo giao diện OLED
│       │   └── oled_manager.cpp        # Vẽ giao diện 128x64 SH1106 hiển thị thông số và icon mạng
│       └── storage/
│           ├── storage_manager.h       # Khai báo bộ nhớ lưu trữ
│           └── storage_manager.cpp     # Lưu trữ cấu hình ngưỡng vào NVS (Preferences)
│
├── adht-weather-app/                    # Phân hệ Di động (Flutter Cross-platform)
│   ├── pubspec.yaml                    # Khai báo dependencies: mqtt_client, supabase_flutter, fl_chart
│   └── lib/
│       ├── main.dart                   # Điểm khởi chạy ứng dụng
│       ├── core/                       # Cấu hình màu sắc, hằng số mạng, helper định dạng
│       ├── data/
│       │   ├── models/                 # Model dữ liệu cảm biến & cấu hình
│       │   └── services/               # Dịch vụ MQTT Client & Supabase API Client
│       └── presentation/
│           ├── providers/              # Quản lý State phản ứng thời gian thực
│           ├── screens/                # Màn hình Dashboard, Biểu đồ lịch sử, Cài đặt điều khiển
│           └── widgets/                # Các thẻ Gauge, Card thông số, Biểu đồ thời tiết
│
└── PROJECT_PLAN.md                     # Tài liệu kế hoạch & đặc tả kỹ thuật dự án
```

---

## 2. SƠ ĐỒ KIẾN TRÚC HỆ THỐNG

Toàn bộ hệ thống vận hành theo luồng truyền thông khép kín, bảo mật và phản ứng tức thì:

```mermaid
flowchart TD
    subgraph NODE["1. TẦNG THIẾT BỊ ĐẦU CUỐI (ESP32 NODE)"]
        Sensors["DHT11 (Nhiệt/Ẩm)<br/>Gàu lật (Mưa)<br/>Chong chóng (Gió)"] -->|Ngắt phần cứng & I2C| Core1["Core 1: Task Sensors & Display"]
        Core1 -->|FreeRTOS Shared State| Core0["Core 0: Task Network & Cloud"]
        Core1 --> OLED["Màn hình OLED SH1106 1.3'"]
        Core1 --> Alert["Còi Buzzer & LED Cảnh Báo"]
    end

    subgraph CLOUD["2. TẦNG ĐÁM MÂY (CLOUD LAYER - 100% FREE TIER)"]
        Broker["MQTT Broker: HiveMQ Cloud<br/>- Cổng bảo mật: 8883 (TLS/SSL)<br/>- Cơ chế LWT: Báo Online/Offline"]
        DB[("Supabase Cloud (PostgreSQL)<br/>- Bảng: weather_logs<br/>- Giao diện: REST API HTTPS")]
    end

    subgraph CLIENT["3. TẦNG GIAO DIỆN NGƯỜI DÙNG (FLUTTER APP)"]
        Dashboard["Màn hình Realtime<br/>(Subscribe MQTT qua TLS/WSS)"]
        Analytics["Màn hình Biểu đồ Lịch sử<br/>(Query Supabase REST API)"]
        Control["Màn hình Điều khiển & Ngưỡng<br/>(Publish MQTT Command/Config)"]
    end

    Core0 -->|MQTT Pub Telemetry (Mỗi 5s)| Broker
    Core0 -->|HTTPS POST Batch (Mỗi 30s)| DB
    Broker <-->|Realtime Pub/Sub| Dashboard
    Broker <-->|Gửi lệnh tức thì| Control
    DB -->|Truy vấn dữ liệu lịch sử| Analytics
```

---

## 3. ĐẶC TẢ PHẦN CỨNG & SƠ ĐỒ NỐI CHÂN (PINOUT)

### 3.1. Bảng phân bổ chân GPIO ESP32 DevKit V1

| Thiết bị / Module | Loại tín hiệu | Chân GPIO | Chức năng kỹ thuật |
|---|---|---|---|
| **Cảm biến DHT11** | Digital (1-Wire) | `GPIO 26` | Thu thập nhiệt độ (°C) và độ ẩm (%), lọc mịn bằng Kalman Filter |
| **Cảm biến Mưa** | Digital (Interrupt) | `GPIO 15` | Ngắt cạnh xuống (`FALLING`), chống rung xung 150ms |
| **Cảm biến Gió** | Digital (Interrupt) | `GPIO 13` | Ngắt cạnh xuống (`FALLING`), chống rung xung 50ms |
| **OLED SH1106 (SDA)** | I2C Data | `GPIO 21` | Giao tiếp dữ liệu màn hình hiển thị |
| **OLED SH1106 (SCL)** | I2C Clock | `GPIO 22` | Xung nhịp đồng bộ I2C 400kHz |
| **Còi Buzzer** | Digital Output | `GPIO 2` | Báo động khi thông số thời tiết vượt ngưỡng nguy hiểm |
| **Đèn LED Trạng thái**| Digital Output | `GPIO 33` | Nhấp nháy báo nhịp hoạt động (Heartbeat) và mất mạng |
| **Nút nhấn SET** | Digital Input | `GPIO 32` | Kéo lên nội (`INPUT_PULLUP`) |
| **Nút nhấn UP** | Digital Input | `GPIO 35` | Chỉ hỗ trợ Input (`INPUT`) |
| **Nút nhấn DOWN** | Digital Input | `GPIO 34` | Chỉ hỗ trợ Input (`INPUT`) |

### 3.2. Công thức tính toán vật lý

1. **Lượng mưa (Rainfall)**:
   - Diện tích phễu hứng nước: $S = 9498.0 \text{ mm}^2$ (bán kính phễu $55 \text{ mm}$).
   - Lượng nước gàu lật: $V = 6.0 \text{ ml}$.
   - Độ dày lớp nước mỗi xung: 
     $$\Delta h = \frac{1\,000\,000}{S} \times \frac{V}{1000} \approx 0.6317 \text{ mm/xung}$$
   - Cường độ mưa tức thời ($\text{mm/h}$):
     $$\text{Rain Rate} = (\text{Số xung} \times \Delta h) \times \frac{3600}{\Delta t_{\text{giây}}}$$

2. **Tốc độ gió (Wind Speed)**:
   - Đường kính trục chong chóng: $D = 208 \text{ mm} = 0.208 \text{ m}$.
   - Chu vi vòng xoay: $C = \pi \times D \approx 0.6535 \text{ m}$.
   - Tốc độ gió tức thời ($\text{m/s}$):
     $$v = \frac{\text{Số xung} \times C}{\Delta t_{\text{giây}}}$$

---

## 4. ĐẶC TẢ GIAO THỨC MẠNG & MQTT TOPICS

- **MQTT Broker**: HiveMQ Cloud Cluster
- **Cổng kết nối**: `8883` (MQTTS - Mã hóa TLS/SSL) hoặc `8884` (WSS)
- **Thiết bị định danh (Client ID)**: `adht_weather_01`

### 4.1. Danh mục Topics

| Topic | Chiều truyền | QoS | Retain | Mô tả chức năng |
|---|---|---|---|---|
| `adht/weather/telemetry` | ESP32 ➔ Broker | 0 | False | Phát số liệu cảm biến chu kỳ 5 giây/lần |
| `adht/weather/status` | ESP32 ➔ Broker | 1 | **True** | Trạng thái Online / Offline (tự động phát qua LWT khi mất điện/mạng) |
| `adht/weather/command` | App ➔ ESP32 | 1 | False | Gửi lệnh kích hoạt (bật còi, đổi trạng thái LED, khởi động lại trạm) |
| `adht/weather/config` | App ➔ ESP32 | 1 | **True** | Gửi cập nhật ngưỡng nhiệt/ẩm/gió để ESP32 lưu vào bộ nhớ NVS |

### 4.2. Cấu trúc bản tin JSON chi tiết

#### 1. Bản tin số liệu định kỳ (`adht/weather/telemetry`):
```json
{
  "device_id": "adht_weather_01",
  "temp": 28.6,
  "humi": 65.4,
  "rain_rate": 0.0,
  "rain_total": 5.2,
  "wind_speed": 2.1,
  "wind_max": 4.5,
  "rssi": -58,
  "uptime": 3600
}
```

#### 2. Bản tin trạng thái & LWT (`adht/weather/status`):
- Trạng thái mất kết nối (LWT tự động gửi khi ESP32 tắt nguồn):
  ```json
  {"status": "offline"}
  ```
- Trạng thái hoạt động bình thường:
  ```json
  {"status": "online", "device": "adht_weather_01", "ip": "192.168.1.15"}
  ```

#### 3. Bản tin điều khiển (`adht/weather/command`):
```json
{
  "cmd": "buzzer",
  "arg": "500"
}
```

#### 4. Bản tin cấu hình ngưỡng (`adht/weather/config`):
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

---

## 5. ĐẶC TẢ CƠ SỞ DỮ LIỆU SUPABASE

### 5.1. Kịch bản SQL tạo bảng (Thực thi trong Supabase SQL Editor)
```sql
-- Tạo bảng lưu trữ lịch sử quan trắc thời tiết
create table weather_logs (
  id bigint generated by default as identity primary key,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  device_id text default 'adht_weather_01',
  temperature float not null,
  humidity float not null,
  rain_rate float not null,
  wind_speed float not null
);

-- Tạo chỉ mục theo mốc thời gian để tối ưu tốc độ truy vấn biểu đồ
create index idx_weather_created_at on weather_logs (created_at desc);

-- Cấu hình chính sách bảo mật Row Level Security (RLS)
alter table weather_logs enable row level security;
create policy "Allow anonymous insert" on weather_logs for insert with check (true);
create policy "Allow anonymous select" on weather_logs for select using (true);
```

### 5.2. Giao thức REST API HTTPS POST
- **Endpoint**: `https://<PROJECT-ID>.supabase.co/rest/v1/weather_logs`
- **Headers**:
  ```http
  Content-Type: application/json
  apikey: <SUPABASE_ANON_KEY>
  Authorization: Bearer <SUPABASE_ANON_KEY>
  Prefer: return=minimal
  ```
- **Payload**:
  ```json
  {
    "device_id": "adht_weather_01",
    "temperature": 28.6,
    "humidity": 65.4,
    "rain_rate": 0.0,
    "wind_speed": 2.1
  }
  ```

---

## 6. ĐẶC TẢ ỨNG DỤNG DI ĐỘNG (FLUTTER MOBILE APP)

### 6.1. Kiến trúc phân tầng (Clean Architecture)
```text
adht-weather-app/lib/
├── core/
│   ├── constants/            # HiveMQ URL, Supabase API Key, Topic definitions
│   ├── theme/                # Màu sắc giao diện (Dark/Light mode, Glassmorphism)
│   └── utils/                # Hàm chuyển đổi đơn vị, định dạng ngày giờ
├── data/
│   ├── models/
│   │   ├── weather_telemetry.dart  # Model cho bản tin MQTT
│   │   └── weather_history.dart    # Model cho bản ghi Supabase
│   └── services/
│       ├── mqtt_client_service.dart   # Kết nối MQTTS, lắng nghe telemetry & gửi command
│       └── supabase_service.dart      # Query lịch sử theo mốc thời gian (6h, 24h, 7d)
└── presentation/
    ├── providers/
    │   └── weather_provider.dart      # Quản lý state dữ liệu thời gian thực và lịch sử
    ├── screens/
    │   ├── dashboard_screen.dart      # Đồng hồ đo thời gian thực, thẻ thông số, badge Online
    │   ├── history_chart_screen.dart  # Biểu đồ fl_chart (nhiệt độ, độ ẩm, gió, mưa)
    │   └── settings_screen.dart       # Gửi cấu hình ngưỡng và kiểm tra còi từ xa
    └── widgets/
        ├── weather_gauge_card.dart    # Thẻ hiển thị số đo dạng đồng hồ
        └── multi_line_chart.dart      # Widget biểu đồ đường tương tác (pan/zoom)
```

### 6.2. Các gói thư viện (Dependencies trong `pubspec.yaml`)
- `mqtt_client: ^10.2.0`: Xử lý giao thức MQTT TLS qua Socket/WebSocket.
- `supabase_flutter: ^2.5.0`: SDK truy vấn cơ sở dữ liệu Supabase.
- `fl_chart: ^0.68.0`: Vẽ biểu đồ đường và biểu đồ cột mượt mà.
- `provider: ^6.1.2`: Quản lý trạng thái luồng dữ liệu (State Management).
- `intl: ^0.19.0`: Xử lý ngày giờ và nhãn mốc thời gian.

---

## 7. LỘ TRÌNH TRIỂN KHAI DỰ ÁN (5 TUẦN)

Toàn bộ nhóm làm việc tập trung trên cùng một Git Repository, phân nhánh tính năng (`feature/firmware`, `feature/mobile-app`):

| Giai đoạn | Nhiệm vụ chính | Phân hệ | Đầu ra nghiệm thu |
|---|---|---|---|
| **Tuần 1** | **Khởi tạo Đám mây & Kiểm thử Mạch**<br/>- Đăng ký cụm HiveMQ Cloud Free & tạo tài khoản kết nối.<br/>- Tạo dự án Supabase & chạy script SQL tạo bảng.<br/>- Kiểm tra nguồn và đường truyền tín hiệu cảm biến ESP32. | Cloud & Hardware | - Cụm HiveMQ & Supabase sẵn sàng.<br/>- Bảng đo kiểm tín hiệu GPIO hoạt động tốt. |
| **Tuần 2** | **Hiệu chuẩn & Vận hành Firmware**<br/>- Điền WiFi và Cloud credentials vào [config.h](file:///home/duongan/Documents/Code/IoT-project/adht-weather-firmware/src/config.h).<br/>- Hiệu chuẩn hệ số gàu lật mưa và chong chóng gió.<br/>- Nạp code và kiểm tra dữ liệu đẩy lên HiveMQ + Supabase. | `adht-weather-firmware` | - ESP32 hoạt động liên tục 24/7.<br/>- OLED hiển thị đầy đủ thông số và trạng thái mạng. |
| **Tuần 3** | **Khởi tạo Flutter & Màn hình Realtime**<br/>- Tạo dự án Flutter trong `adht-weather-app`.<br/>- Xây dựng service kết nối MQTT Client nhận `telemetry`.<br/>- Thiết kế Dashboard hiển thị số đo và Badge Online/Offline. | `adht-weather-app` | - Ứng dụng chạy trên Android/iOS.<br/>- Nhận dữ liệu Realtime độ trễ < 100ms. |
| **Tuần 4** | **Biểu đồ Lịch sử & Điều khiển Cảnh báo**<br/>- Tích hợp `fl_chart` kết nối Supabase REST API.<br/>- Làm bộ lọc thời gian: 6 giờ, 24 giờ, 7 ngày.<br/>- Màn hình Settings cho phép đổi ngưỡng cảnh báo và test còi. | `adht-weather-app` | - Biểu đồ trực quan hóa dữ liệu theo ngày/tuần.<br/>- Điều khiển còi và lưu cấu hình ngưỡng từ xa. |
| **Tuần 5** | **Kiểm thử Hệ thống, Đóng gói & Báo cáo**<br/>- Stress test: Mất WiFi, mất điện đột ngột, phục hồi tự động.<br/>- Xuất bản file cài đặt Android `.apk`.<br/>- Hoàn thiện hộp bảo vệ ngoài trời và tài liệu báo cáo. | Toàn hệ thống | - File cài đặt `ADHT_Weather.apk`.<br/>- Trạm thời tiết hoàn thiện và Slide thuyết trình. |

---

## 8. KẾ HOẠCH KIỂM THỬ & ĐÁNH GIÁ CHẤT LƯỢNG (QA/QC)

1. **Kiểm thử Tính Chịu Lỗi Mạng (Fault Tolerance)**:
   - *Tình huống*: Tắt nguồn bộ phát WiFi trong 5 phút rồi bật lại.
   - *Kỳ vọng*: ESP32 tự động nhận biết mất kết nối, chuyển hiển thị `W:--` trên OLED, tiếp tục đo cảm biến ngắt bình thường và tự động kết nối lại mạng ngay khi có sóng.
2. **Kiểm thử Cơ chế Báo trạng thái tức thì (LWT Test)**:
   - *Tình huống*: Rút nguồn adapter cấp cho ESP32.
   - *Kỳ vọng*: Sau 5–10 giây, HiveMQ tự động phát bản tin LWT, Mobile App lập tức chuyển trạng thái trạm sang `Offline`.
3. **Kiểm thử Độ Bền & Lưu Trữ Dữ Liệu (Endurance Test)**:
   - *Tình huống*: Cho trạm hoạt động liên tục 24 giờ ngoài môi trường thực tế.
   - *Kỳ vọng*: Supabase ghi nhận khoảng 2.880 bản ghi (với chu kỳ 30 giây/lần), biểu đồ hiển thị liên tục không bị gián đoạn.
4. **Kiểm thử Độ Trễ Điều Khiển Từ Xa (Remote Command Latency)**:
   - *Tình huống*: Bấm nút "Kích hoạt Còi" trên Mobile App.
   - *Kỳ vọng*: ESP32 nhận lệnh qua MQTT và phát còi sau chưa đầy 200ms.

---

## 9. HƯỚNG DẪN CÀI ĐẶT & VẬN HÀNH NHANH (QUICKSTART)

### 9.1. Nạp Firmware ESP32
1. Mở VS Code tại thư mục `adht-weather-firmware`.
2. Mở file [src/config.h](file:///home/duongan/Documents/Code/IoT-project/adht-weather-firmware/src/config.h) và điền:
   - `DEFAULT_WIFI_SSID` và `DEFAULT_WIFI_PASS`.
   - `MQTT_BROKER_HOST`, `MQTT_USERNAME`, `MQTT_PASSWORD`.
   - `SUPABASE_URL` và `SUPABASE_ANON_KEY`.
3. Cắm cáp USB nối ESP32 vào máy tính.
4. Bấm nút **`→` (PlatformIO: Upload)** ở thanh dưới cùng của VS Code để nạp code.
5. Mở **Serial Monitor** (115200 baud) để kiểm tra log xác nhận kết nối thành công.

### 9.2. Khởi tạo & Chạy Ứng dụng Di động
1. Mở cửa sổ dòng lệnh tại thư mục `adht-weather-app`:
   ```bash
   cd adht-weather-app
   flutter create --org com.adht .
   flutter pub add mqtt_client supabase_flutter fl_chart provider intl
   flutter run
   ```

---
*Tài liệu này là đặc tả kỹ thuật chính thức và lộ trình chuẩn cho toàn bộ dự án ADHT Weather Station.*
