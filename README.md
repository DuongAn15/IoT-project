# 🌦️ ADHT Smart Weather Station & IoT Cloud Ecosystem

Hệ thống trạm quan trắc thời tiết thông minh phát triển bởi nhóm **ADHT**.

## 📁 Cấu trúc Repository (Monorepo)
- **`adht-weather-firmware/`**: Mã nguồn nhúng cho vi điều khiển ESP32 (viết bằng C++ trên PlatformIO).
  - Tận dụng Dual-Core FreeRTOS.
  - Kết nối MQTT bảo mật TLS qua HiveMQ Cloud.
  - Lưu trữ dữ liệu lịch sử vào Supabase Cloud (PostgreSQL REST API).
  - Hiển thị thông số thời gian thực lên màn hình OLED SH1106.
- **`adht-weather-app/`**: Ứng dụng di động đa nền tảng viết bằng Flutter (Dart).
- **`PROJECT_PLAN.md`**: Bản đặc tả kiến trúc kỹ thuật và kế hoạch chi tiết của dự án.

