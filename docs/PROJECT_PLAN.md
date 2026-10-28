# 🌦️ KẾ HOẠCH DỰ ÁN: TRẠM QUAN TRẮC THỜI TIẾT THÔNG MINH ADHT

> **Đơn vị phát triển**: Nhóm ADHT  
> **Mô hình Repository**: Monorepo (Quản lý tập trung toàn bộ Firmware và Mobile App trong 1 Repository duy nhất)  
> **Công nghệ lõi**: ESP32 (FreeRTOS) + EMQX Cloud Serverless (MQTT TLS) + Supabase (PostgreSQL REST API) + Flutter Mobile App  

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
│   ├── platformio.ini                  # Cấu hình board esp32doit-devkit-v1, partition huge_app, load_env.py
│   ├── load_env.py                     # Pre-build script trích xuất biến môi trường từ .env thành cờ -D
│   ├── .env.example                    # Template cấu hình mẫu WiFi, EMQX Credentials
│   ├── .env                            # [Bảo mật] Chứa thông tin WiFi và EMQX thật (không commit vào Git)
│   ├── include/                        # Header dùng chung
│   ├── lib/                            # Thư viện cục bộ (Adafruit GFX, SH110X, DHT, Kalman)
│   └── src/
│       ├── config.h                    # Định nghĩa Hardware Pinout, Timing intervals, MQTT Topics
│       ├── types.h                     # Cấu trúc dữ liệu WeatherData, SystemConfig, NetworkStatus
│       ├── main.cpp                    # Khởi tạo và điều phối 4 Task FreeRTOS trên 2 Core
│       ├── sensors/
│       │   ├── sensor_manager.h        # Khai báo bộ đọc cảm biến
│       │   └── sensor_manager.cpp      # Đọc DHT11 (bộ lọc Kalman), ngắt đo xung Mưa và Gió
│       ├── network/
│       │   ├── wifi_manager.h/.cpp     # Quản lý kết nối WiFi và cơ chế tự động kết nối lại
│       │   └── mqtt_manager.h/.cpp     # Client MQTT kết nối EMQX Cloud Serverless (TLS 8883), LWT, Pub/Sub
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

Hệ thống được thiết kế theo mô hình **Event-driven IoT Architecture**, tối ưu hóa hiệu năng vi điều khiển và đảm bảo luồng truyền thông thời gian thực bảo mật:

```mermaid
flowchart TD
    subgraph NODE["1. TẦNG THIẾT BỊ ĐẦU CUỐI (ESP32 NODE)"]
        Sensors["DHT11 (Nhiệt/Ẩm)<br/>Gàu lật (Mưa)<br/>Chong chóng (Gió)"] -->|Ngắt phần cứng & I2C| Core1["Core 1: Task Sensors & Display"]
        Core1 -->|FreeRTOS Shared State| Core0["Core 0: Task Network & Cloud"]
        Core1 --> OLED["Màn hình OLED SH1106 1.3'"]
        Core1 --> Alert["Còi Buzzer & LED Cảnh Báo"]
    end

    subgraph CLOUD["2. TẦNG ĐÁM MÂY (CLOUD LAYER - EMQX & SUPABASE)"]
        Broker["MQTT Broker: EMQX Cloud Serverless<br/>- Cổng bảo mật: 8883 (TLS/SSL)<br/>- Cơ chế LWT: Báo Online/Offline"]
        RuleEngine["EMQX Data Integration (Rule Engine)<br/>- SQL parse JSON payload<br/>- HTTP Server Sink (Webhook POST)"]
        DB[("Supabase Cloud (PostgreSQL)<br/>- Bảng: weather_logs<br/>- REST API HTTPS")]
        Broker -->|Kích hoạt Rule Engine| RuleEngine
        RuleEngine -->|Tự động HTTPS POST| DB
    end

    subgraph CLIENT["3. TẦNG GIAO DIỆN NGƯỜI DÙNG (FLUTTER APP)"]
        Dashboard["Màn hình Realtime<br/>(Subscribe MQTT qua TLS/WSS)"]
        Analytics["Màn hình Biểu đồ Lịch sử<br/>(Query Supabase REST API)"]
        Control["Màn hình Điều khiển & Ngưỡng<br/>(Publish MQTT Command/Config)"]
    end

    Core0 -->|MQTT Pub Telemetry (Mỗi 3s)| Broker
    Broker <-->|Realtime Pub/Sub| Dashboard
    Broker <-->|Gửi lệnh tức thì| Control
    DB -->|Truy vấn dữ liệu lịch sử| Analytics
```

### 💡 Điểm cải tiến cốt lõi trong Kiến trúc:
- **Tách bạch trách nhiệm (Decoupling)**: ESP32 **không** phải gánh kết nối HTTPS REST cồng kềnh tới Supabase. Việc mở 2 kết nối TLS đồng thời (MQTT + HTTPS) trên ESP32 làm cạn kiệt RAM và dễ gây Crash.
- **Luồng dữ liệu tinh gọn**: ESP32 chỉ cần duy trì duy nhất 1 kết nối nhẹ MQTTS (TLS 8883) để gửi dữ liệu định kỳ mỗi **3 giây** lên **EMQX Cloud Serverless**.
- **Cầu nối EMQX Data Integration**: EMQX Cloud đóng vai trò trạm trung chuyển, sử dụng **Rule Engine** bóc tách gói tin và tự động kích hoạt **HTTP Server Sink** để ghi trực tiếp vào **Supabase Database**.
- **Hiệu năng cao cho Mobile App**: Flutter App nhận dữ liệu tức thì từ MQTT (<100ms) cho Dashboard, đồng thời truy vấn Supabase REST API khi cần vẽ biểu đồ phân tích xu hướng (1H, 6H, 24H, 3D, 7D).

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

- **MQTT Broker**: EMQX Cloud Serverless
- **Cổng kết nối**: `8883` (MQTTS - Mã hóa TLS/SSL) hoặc `8884` (WSS)
- **Thiết bị định danh (Client ID)**: `adht_weather_01`

### 4.1. Danh mục Topics

| Topic | Chiều truyền | QoS | Retain | Mô tả chức năng |
|---|---|---|---|---|
| `adht/weather/telemetry` | ESP32 ➔ Broker | 0 | False | Phát số liệu cảm biến chu kỳ 3 giây/lần (EMQX tự forward vào Supabase) |
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

## 5. ĐẶC TẢ CƠ SỞ DỮ LIỆU & CẦU NỐI EMQX DATA INTEGRATION

Hệ thống áp dụng kiến trúc **Serverless IoT Pipeline**:
$$\text{ESP32 Nodes} \xrightarrow[\text{MQTTS 8883}]{\text{3 giây/lần}} \text{EMQX Cloud Serverless} \xrightarrow[\text{Rule Engine}]{\text{HTTP Server Sink}} \text{Supabase Database (PostgreSQL)}$$

ESP32 **không** gửi HTTP trực tiếp đến cơ sở dữ liệu. Toàn bộ tác vụ chuyển đổi và lưu trữ được thực hiện tự động thông qua **EMQX Data Integration (Rule Engine)**.

### 5.1. Kịch bản SQL khởi tạo bảng (Thực thi trong Supabase SQL Editor)
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

### 5.2. Cấu hình Cầu nối Tự động EMQX Data Integration ➔ Supabase

#### 1. Lợi ích kỹ thuật của giải pháp:
- **Tối ưu tài nguyên vi điều khiển**: ESP32 chỉ cần duy trì duy nhất 1 kết nối nhẹ MQTT TLS 8883, giải phóng hơn 40KB bộ nhớ RAM Heap (không phải duy trì thêm mbedTLS client cho HTTPS POST).
- **Độ tin cậy & Chịu lỗi cao**: EMQX Cloud Serverless tích hợp bộ nhớ đệm (Buffer Queue) và cơ chế thử lại (Retry) tự động nếu đường truyền tới Supabase bị trễ hoặc ngắt quãng tạm thời.
- **Tách biệt kiến trúc (Decoupling)**: Khi cần thay đổi cấu trúc bảng, thêm cơ sở dữ liệu mới (TimescaleDB, InfluxDB, Kafka) hay đổi secret key, quản trị viên chỉ cần điều chỉnh cấu hình trên EMQX Console mà không cần nạp lại firmware cho hàng trăm node cảm biến ngoài hiện trường.

#### 2. Bước 1: Tạo Connector (HTTP Server) trên EMQX Cloud Console
- **Menu**: `Data Integration` ➔ `Connectors` ➔ `+ New Connector` (Chọn **HTTP Server**).
- **Connector Name**: `c_supabase_rest`
- **URL**: `https://<PROJECT-ID>.supabase.co/rest/v1` (Thay `<PROJECT-ID>` bằng ID dự án Supabase thực tế).
- **Headers**:
  | Key | Value |
  |---|---|
  | `accept` | `application/json` |
  | `content-type` | `application/json` |
  | `connection` | `keep-alive` |
- Nhấn **Test** để xác nhận kết nối xanh, sau đó chọn **New / Save**.

#### 3. Bước 2: Tạo Rule Engine (Trích xuất SQL)
- **Menu**: `Data Integration` ➔ `Rules` ➔ `+ New Rule`.
- **Data Source**: `Message Publish`
- **Topic Filter**: `"adht/weather/telemetry", "adht/weather/+/telemetry"`
- **SQL Editor**:
  ```sql
  SELECT 
    payload.device_id as device_id, 
    payload.temp as temperature, 
    payload.humi as humidity, 
    payload.rain_rate as rain_rate, 
    payload.wind_speed as wind_speed 
  FROM 
    "adht/weather/telemetry", "adht/weather/+/telemetry"
  ```

#### 4. Bước 3: Tạo Action (Sink - HTTP Server)
- **Action Type**: `HTTP Server`
- **Connector**: Chọn Connector `c_supabase_rest` đã tạo ở Bước 1.
- **URL Path**: `/weather_logs`
- **Method**: `POST`
- **Headers bổ sung**:
  | Key | Value |
  |---|---|
  | `apikey` | `<SUPABASE_ANON_KEY>` |
  | `Authorization` | `Bearer <SUPABASE_ANON_KEY>` |
  | `Prefer` | `return=minimal` |
- **Body Template** (Định dạng JSON gửi đến Supabase REST API):
  ```json
  {
    "device_id": "${device_id}",
    "temperature": ${temperature},
    "humidity": ${humidity},
    "rain_rate": ${rain_rate},
    "wind_speed": ${wind_speed}
  }
  ```

#### 5. Kết quả Xác thực Thực tế (Live Verification)
- Sau khi kích hoạt Rule, mỗi khi ESP32 phát bản tin MQTT chu kỳ 3 giây/lần lên topic `adht/weather/telemetry`, EMQX Cloud Rule Engine lập tức trích xuất các trường `temp`, `humi`, `rain_rate`, `wind_speed` và gửi HTTP POST đến Supabase.
- Dữ liệu trong bảng `weather_logs` trên Supabase được ghi nhận liên tục theo đúng mốc thời gian thực tế cách nhau 3.0 giây mỗi dòng.

---

## 6. ĐẶC TẢ ỨNG DỤNG DI ĐỘNG (FLUTTER MOBILE APP)

Ứng dụng di động **ADHT Weather App** được xây dựng bằng **Flutter (Dart)** theo mô hình kiến trúc phân tầng sạch (Clean Architecture). Ứng dụng đóng vai trò là trung tâm giám sát & điều khiển toàn diện của hệ sinh thái trạm thời tiết, kết hợp hài hòa giữa **giám sát thời gian thực** và **phân tích dữ liệu lịch sử**.

### 6.1. Kiến trúc Đa luồng Dữ liệu (Dual Data Streams Architecture)

Ứng dụng di động không phụ thuộc vào một nguồn duy nhất mà tích hợp đồng thời 2 kênh truyền thông chuyên biệt nhằm tối ưu hóa trải nghiệm người dùng và tiết kiệm tài nguyên mạng:

```text
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                   ADHT WEATHER MOBILE APP                               │
└────────────────────────────────────────────┬────────────────────────────────────────────┘
                                             │
               ┌─────────────────────────────┴─────────────────────────────┐
               ▼                                                           ▼
┌───────────────────────────────┐                           ┌───────────────────────────────┐
│    KÊNH MQTT REALTIME & LỆNH  │                           │   KÊNH TRUY VẤN LỊCH SỬ REST  │
│  (EMQX Cloud qua TLS/WSS)     │                           │      (Supabase Database)      │
├───────────────────────────────┤                           ├───────────────────────────────┤
│ • Nhận Telemetry mỗi 3s       │                           │ • Truy vấn lịch sử quan trắc  │
│ • Cập nhật tức thì Dashboard  │                           │ • Bộ lọc: 1H, 6H, 24H, 3D, 7D │
│ • Nhận LWT Online/Offline     │                           │ • Vẽ biểu đồ xu hướng fl_chart│
│ • Gửi lệnh còi, LED, reset    │                           │ • Thống kê Min/Max/Avg        │
│ • Gửi cấu hình ngưỡng báo động│                           │ • Phân tích lượng mưa lũy kế  │
└───────────────────────────────┘                           └───────────────────────────────┘
```

#### 1. Luồng Thời gian thực & Điều khiển (Real-time Stream via EMQX):
- **Dashboard Realtime**: Subscribe topic `adht/weather/telemetry` để nhận dữ liệu mỗi **3 giây/lần**. Các đồng hồ đo (Gauges) và thẻ hiển thị (Nhiệt độ, Độ ẩm, Tốc độ gió, Lượng mưa, Tín hiệu WiFi RSSI) tự động nhảy số với độ trễ < 100ms mà hoàn toàn **không cần truy vấn Database**, giúp tiết kiệm tối đa quota mạng.
- **Trạng thái trạm (Online/Offline Badge)**: Subscribe topic `adht/weather/status` để biết chính xác khi nào trạm bị mất nguồn/mất mạng thông qua cơ chế MQTT Last Will and Testament (LWT).
- **Gửi lệnh điều khiển tức thì (Downlink Commands)**: Publish gói tin JSON lên topic `adht/weather/command` để bật còi cảnh báo khẩn cấp, bật đèn LED kiểm tra đêm hoặc ra lệnh khởi động lại ESP32.
- **Cập nhật ngưỡng từ xa**: Publish gói tin JSON lên topic `adht/weather/config` với cờ `retain = true` để ESP32 tự động lưu ngưỡng mới vào bộ nhớ Flash NVS.

#### 2. Luồng Lịch sử & Phân tích (Historical Analytics via Supabase):
- **Biểu đồ trực quan hóa**: Sử dụng thư viện `fl_chart` để vẽ biểu đồ đường trượt đa điểm (pan/zoom) cho nhiệt độ, độ ẩm, tốc độ gió và biểu đồ cột cho lượng mưa.
- **Bộ lọc linh hoạt (5 mốc thời gian)**: Cho phép người dùng chuyển đổi nhanh giữa các mốc: `1 giờ qua` (1H), `6 giờ qua` (6H), `24 giờ qua` (24H), `3 ngày qua` (3D) và `7 ngày qua` (7D).
- **Thống kê tổng hợp**: Tự động tính toán các chỉ số quan trọng trong khoảng thời gian đã chọn: Nhiệt độ đỉnh (Max), Nhiệt độ thấp nhất (Min), Độ ẩm trung bình và Tổng lượng mưa tích lũy.

---

### 6.2. Đặc tả các Màn hình Chức năng

```text
├── 1. Dashboard Screen (Màn hình chính - Realtime Monitoring)
│   ├── Header: Tên trạm, Badge Online/Offline (LWT), Thời gian cập nhật gần nhất
│   ├── Thẻ Gauge chính: Nhiệt độ (°C) & Độ ẩm (%) với vòng tròn gradient màu sắc
│   ├── Thẻ phụ: Tốc độ gió tức thời (m/s), Cường độ mưa (mm/h), Mưa tích lũy (mm)
│   ├── Thẻ hệ thống: Cường độ tín hiệu WiFi (RSSI dBm), Thời gian hoạt động (Uptime)
│   └── Nút tắt/bật còi khẩn cấp nhanh (Quick Buzzer Action)
│
├── 2. Analytics Screen (Màn hình Lịch sử & Biểu đồ)
│   ├── Thanh chọn mốc thời gian: [ 1H ] [ 6H ] [ 24H ] [ 3D ] [ 7D ]
│   ├── Card thống kê nhanh: Nhiệt độ Min/Max, Gió giật lớn nhất, Tổng mưa tích lũy
│   ├── Biểu đồ đường kép (Multi-line Chart): Diễn biến Nhiệt độ & Độ ẩm theo thời gian
│   ├── Biểu đồ diện tích (Area Chart): Tốc độ gió qua các mốc thời gian
│   └── Biểu đồ cột (Bar Chart): Lượng mưa đo được theo từng mốc giờ/ngày
│
└── 3. Settings Screen (Màn hình Cấu hình & Điều khiển từ xa)
    ├── Điều khiển thiết bị:
    │   ├── Nút "Kích hoạt Còi kiểm tra" (arg: 500ms)
    │   ├── Công tắc "Đèn LED trạng thái" (Toggle LED)
    │   └── Nút "Khởi động lại Trạm ESP32" (Reboot command)
    └── Cài đặt ngưỡng cảnh báo tự động:
        ├── Thanh trượt (Slider): Ngưỡng nhiệt độ cao tối đa (Mặc định 38.0°C)
        ├── Thanh trượt (Slider): Ngưỡng độ ẩm tối đa (Mặc định 90.0%)
        ├── Thanh trượt (Slider): Ngưỡng tốc độ gió nguy hiểm (Mặc định 15.0 m/s)
        ├── Công tắc kích hoạt còi tự động khi chạm ngưỡng
        └── Nút "Lưu Cấu Hình" (Gửi qua MQTT Config topic)
```

---

### 6.3. Kiến trúc Cấu trúc Thư mục Clean Architecture
```text
adht-weather-app/lib/
├── core/
│   ├── constants/            # EMQX Cloud Broker URL, Supabase API Key, MQTT Topics
│   ├── theme/                # Màu sắc giao diện (Dark/Light mode, Modern Glassmorphism)
│   └── utils/                # Hàm format ngày giờ, chuyển đổi đơn vị đo lường
├── data/
│   ├── models/
│   │   ├── weather_telemetry.dart  # Parse gói tin JSON nhận từ MQTT Telemetry
│   │   ├── weather_history.dart    # Model dữ liệu bản ghi từ Supabase PostgreSQL
│   │   └── alert_config.dart       # Model cấu hình ngưỡng cảnh báo
│   └── services/
│       ├── mqtt_client_service.dart   # Kết nối MQTTS/WSS, Subscribe Telemetry & Publish Command/Config
│       └── supabase_service.dart      # Query cơ sở dữ liệu Supabase theo mốc thời gian (1h, 6h, 24h, 3d, 7d)
└── presentation/
    ├── providers/
    │   └── weather_provider.dart      # Quản lý state phản ứng thời gian thực (Provider/ChangeNotifier)
    ├── screens/
    │   ├── dashboard_screen.dart      # Màn hình Dashboard thời gian thực
    │   ├── history_chart_screen.dart  # Màn hình Biểu đồ lịch sử fl_chart
    │   └── settings_screen.dart       # Màn hình Điều khiển còi và Cài đặt ngưỡng
    └── widgets/
        ├── weather_gauge_card.dart    # Thẻ đồng hồ đo vòng cung (Circular Gauge)
        ├── status_badge.dart          # Huy hiệu trạng thái Online / Offline
        └── history_line_chart.dart    # Widget biểu đồ tương tác chạm điểm hiển thị tooltip
```

### 6.4. Các gói thư viện chính (Dependencies trong `pubspec.yaml`)
- `mqtt_client: ^10.2.0`: Kết nối MQTT bảo mật TLS qua Socket hoặc WebSocket (WSS).
- `supabase_flutter: ^2.5.0`: SDK chính thức truy vấn dữ liệu từ bảng PostgreSQL trên Supabase.
- `fl_chart: ^0.68.0`: Thư viện vẽ biểu đồ hàng đầu cho Flutter (LineChart, BarChart).
- `provider: ^6.1.2`: Quản lý trạng thái luồng dữ liệu phản ứng (Reactive State Management).
- `intl: ^0.19.0`: Xử lý định dạng ngày tháng, giờ giấc và đơn vị số học.

---

## 7. LỘ TRÌNH TRIỂN KHAI DỰ ÁN (5 TUẦN)

Toàn bộ nhóm làm việc tập trung trên cùng một Git Repository, phân nhánh tính năng (`feature/firmware`, `feature/mobile-app`):

| Giai đoạn | Nhiệm vụ chính | Phân hệ | Đầu ra nghiệm thu |
|---|---|---|---|
| **Tuần 1** | **Khởi tạo Đám mây & Kiểm thử Mạch**<br/>- Đăng ký cụm EMQX Cloud Serverless Free & tạo tài khoản kết nối.<br/>- Tạo dự án Supabase & chạy script SQL tạo bảng.<br/>- Kiểm tra nguồn và đường truyền tín hiệu cảm biến ESP32. | Cloud & Hardware | - Cụm EMQX Cloud & Supabase sẵn sàng.<br/>- Bảng đo kiểm tín hiệu GPIO hoạt động tốt. |
| **Tuần 2** | **Hiệu chuẩn & Vận hành Firmware**<br/>- Tạo file `.env` từ `.env.example`, điền thông số WiFi & EMQX Cloud credentials.<br/>- Hiệu chuẩn hệ số gàu lật mưa và chong chóng gió.<br/>- Nạp code và kiểm tra dữ liệu đẩy lên EMQX Cloud ➔ Supabase. | `adht-weather-firmware` | - ESP32 hoạt động liên tục 24/7.<br/>- OLED hiển thị đầy đủ thông số và trạng thái mạng.<br/>- Dữ liệu tự động xuất hiện trên Supabase qua EMQX. |
| **Tuần 3** | **Khởi tạo Flutter & Màn hình Realtime**<br/>- Tạo dự án Flutter trong `adht-weather-app`.<br/>- Xây dựng service kết nối MQTT Client nhận `telemetry`.<br/>- Thiết kế Dashboard hiển thị số đo và Badge Online/Offline. | `adht-weather-app` | - Ứng dụng chạy trên Android/iOS.<br/>- Nhận dữ liệu Realtime độ trễ < 100ms. |
| **Tuần 4** | **Biểu đồ Lịch sử & Điều khiển Cảnh báo**<br/>- Tích hợp `fl_chart` kết nối Supabase REST API.<br/>- Làm bộ lọc thời gian: 1H, 6H, 24H, 3D, 7D.<br/>- Màn hình Settings cho phép đổi ngưỡng cảnh báo và test còi. | `adht-weather-app` | - Biểu đồ trực quan hóa dữ liệu theo giờ/ngày/tuần.<br/>- Điều khiển còi và lưu cấu hình ngưỡng từ xa. |
| **Tuần 5** | **Kiểm thử Hệ thống, Đóng gói & Báo cáo**<br/>- Stress test: Mất WiFi, mất điện đột ngột, phục hồi tự động.<br/>- Xuất bản file cài đặt Android `.apk`.<br/>- Hoàn thiện hộp bảo vệ ngoài trời và tài liệu báo cáo. | Toàn hệ thống | - File cài đặt `ADHT_Weather.apk`.<br/>- Trạm thời tiết hoàn thiện và Slide thuyết trình. |

---

## 8. KẾ HOẠCH KIỂM THỬ & ĐÁNH GIÁ CHẤT LƯỢNG (QA/QC)

1. **Kiểm thử Tính Chịu Lỗi Mạng (Fault Tolerance)**:
   - *Tình huống*: Tắt nguồn bộ phát WiFi trong 5 phút rồi bật lại.
   - *Kỳ vọng*: ESP32 tự động nhận biết mất kết nối, chuyển hiển thị `W:--` trên OLED, tiếp tục đo cảm biến ngắt bình thường và tự động kết nối lại mạng ngay khi có sóng.
2. **Kiểm thử Cơ chế Báo trạng thái tức thì (LWT Test)**:
   - *Tình huống*: Rút nguồn adapter cấp cho ESP32.
   - *Kỳ vọng*: Sau 5–10 giây, EMQX Cloud tự động phát bản tin LWT, Mobile App lập tức chuyển trạng thái trạm sang `Offline`.
3. **Kiểm thử Độ Bền & Lưu Trữ Dữ Liệu (Endurance Test)**:
   - *Tình huống*: Cho trạm hoạt động liên tục 24 giờ ngoài môi trường thực tế.
   - *Kỳ vọng*: Supabase ghi nhận các bản ghi đều đặn mỗi 3 giây từ EMQX Data Integration, biểu đồ trên ứng dụng Flutter hiển thị liên tục không bị gián đoạn.
4. **Kiểm thử Độ Trễ Điều Khiển Từ Xa (Remote Command Latency)**:
   - *Tình huống*: Bấm nút "Kích hoạt Còi" trên Mobile App.
   - *Kỳ vọng*: ESP32 nhận lệnh qua MQTT và phát còi sau chưa đầy 200ms.

---

## 9. HƯỚNG DẪN CÀI ĐẶT & VẬN HÀNH NHANH (QUICKSTART)

### 9.1. Nạp Firmware ESP32
1. Mở thư mục `adht-weather-firmware` trong VS Code.
2. Tạo file `.env` (dựa trên mẫu `.env.example`) và điền thông tin mạng của bạn:
   ```ini
   WIFI_SSID="Tên_WiFi"
   WIFI_PASS="Mật_Khẩu_WiFi"
   MQTT_HOST="xxxxxxxx.ala.asia-southeast1.emqxsl.com"
   MQTT_PORT=8883
   MQTT_USER="adht_device"
   MQTT_PASS="Mật_Khẩu_MQTTS"
   DEVICE_ID="adht_weather_01"
   ```
   *(Lưu ý: Không cần điền Supabase Key trên ESP32 vì EMQX Cloud sẽ tự động chuyển tiếp dữ liệu vào Supabase).*
3. Cắm cáp Micro-USB nối ESP32 vào máy tính.
4. Bấm nút **PlatformIO: Upload** (`→`) ở thanh công cụ dưới cùng.
5. Mở **Serial Monitor** với tốc độ `115200` baud để kiểm tra log kết nối WiFi và MQTT.

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
