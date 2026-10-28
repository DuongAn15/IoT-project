# 🌦️ ADHT Smart Weather Station & IoT Cloud Ecosystem

Hệ thống trạm quan trắc thời tiết thông minh phát triển bởi nhóm **ADHT**.

## 🚀 Luồng Kiến Trúc Dữ Liệu (Serverless Pipeline)
```text
[ESP32 Node] ──(MQTTS TLS: 8883 / 3s)──► [EMQX Cloud Broker]
                                                │
                                       (Rule Engine + HTTP Sink)
                                                ▼
[Flutter Mobile App] ◄──(REST API Query)── [Supabase Database]
        ▲
        └───────────────(MQTT Realtime)─────────┘
```

1. **ESP32 Node**: Thu thập dữ liệu cảm biến DHT11 (bộ lọc Kalman), gàu lật mưa, chong chóng gió, hiển thị OLED SH1106 và publish gói tin MQTT mỗi **3 giây** lên **EMQX Cloud Serverless** qua cổng bảo mật TLS `8883`.
2. **EMQX Cloud Serverless**: Tiếp nhận bản tin MQTT, kích hoạt **Rule Engine** bóc tách các trường dữ liệu và tự động kích hoạt **HTTP Server Sink (Webhook POST)** trực tiếp đến **Supabase REST API**.
3. **Supabase Cloud**: Cơ sở dữ liệu PostgreSQL lưu trữ lịch sử quan trắc vào bảng `weather_logs`.
4. **Flutter Mobile App**: Nhận dữ liệu Realtime (<100ms) qua MQTT cho màn hình Dashboard và truy vấn Supabase REST API để vẽ biểu đồ phân tích xu hướng lịch sử.

## 📁 Cấu trúc Repository (Monorepo)
- **`adht-weather-firmware/`**: Mã nguồn nhúng cho vi điều khiển ESP32 (viết bằng C++ trên PlatformIO).
  - Tận dụng Dual-Core FreeRTOS (Core 0: Network/MQTT, Core 1: Sensors/Display).
  - Kết nối MQTT bảo mật TLS cổng 8883 qua **EMQX Cloud Serverless**.
  - Không cần gửi trực tiếp HTTP tới Supabase từ vi điều khiển (giúp tiết kiệm RAM, tránh lỗi Heap và giảm tải CPU).
  - Hiển thị thông số thời gian thực lên màn hình OLED SH1106.
  - Quản lý bảo mật thông tin nhạy cảm (WiFi, MQTT credentials) qua file `.env`.
- **`adht-weather-app/`**: Ứng dụng di động đa nền tảng viết bằng Flutter (Dart).
- **`docs/`**: Thư mục tài liệu kỹ thuật dự án:
  - **[`PROJECT_PLAN.md`](file:///home/duongan/Documents/Code/IoT-project/docs/PROJECT_PLAN.md)**: Bản đặc tả kiến trúc kỹ thuật và kế hoạch chi tiết của dự án.
  - **[`FIRMWARE_REFINEMENT_PLAN.md`](file:///home/duongan/Documents/Code/IoT-project/docs/FIRMWARE_REFINEMENT_PLAN.md)**: Báo cáo phân tích chuyên sâu 11 vấn đề kỹ thuật và lộ trình tinh chỉnh firmware ESP32.
