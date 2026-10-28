# 📱 ADHT Weather Station - Mobile Application

Ứng dụng di động đa nền tảng (Android & iOS) thuộc hệ sinh thái **Trạm quan trắc thời tiết thông minh ADHT**.

Ứng dụng đảm nhận **3 vai trò cốt lõi**:
1. **Giám sát thời gian thực (Realtime Dashboard)**: Lắng nghe bản tin MQTT mỗi 3 giây từ EMQX Cloud để cập nhật số đo nhiệt độ, độ ẩm, gió, mưa với độ trễ < 100ms.
2. **Biểu đồ & Phân tích lịch sử (Historical Analytics)**: Truy vấn cơ sở dữ liệu Supabase để vẽ biểu đồ diễn biến thời tiết theo 1H, 6H, 24H, 3D, 7D bằng thư viện `fl_chart`.
3. **Điều khiển & Cài đặt từ xa (Remote Control)**: Gửi lệnh bật còi báo động, kiểm tra LED, reboot trạm và cập nhật ngưỡng cảnh báo xuống ESP32 qua các MQTT topics chuyên biệt.

---

## 🚀 Công nghệ sử dụng
- **Framework**: [Flutter](https://flutter.dev/) (Dart SDK)
- **Giao thức thời gian thực & Điều khiển**: MQTT qua WebSocket (`wss://`) hoặc TLS Socket (`mqtts://`) kết nối với **EMQX Cloud Serverless**
- **Cơ sở dữ liệu & Phân tích lịch sử**: **Supabase Cloud** (PostgreSQL REST API)
- **Thư viện biểu đồ**: `fl_chart` (Vẽ biểu đồ đường cong nhiệt độ, độ ẩm và biểu đồ cột lượng mưa)
- **Quản lý trạng thái (State Management)**: `provider`

---

## 📂 Kiến trúc Thư mục Clean Architecture
```text
adht-weather-app/
├── lib/
│   ├── main.dart                      # Điểm khởi chạy ứng dụng
│   ├── core/                          # Hằng số (EMQX/Supabase API), Theme, Helpers
│   ├── data/
│   │   ├── models/                    # Model dữ liệu thời tiết & cấu hình
│   │   └── services/                  # MqttClientService & SupabaseService
│   └── presentation/
│       ├── providers/                 # WeatherProvider (quản lý state phản ứng)
│       ├── screens/
│       │   ├── dashboard_screen.dart  # Màn hình số đo thời gian thực & trạng thái Online (MQTT)
│       │   ├── analytics_screen.dart  # Màn hình biểu đồ phân tích 1h, 6h, 24h, 3d, 7d (Supabase)
│       │   └── control_screen.dart    # Màn hình điều khiển còi & cài đặt ngưỡng (MQTT)
│       └── widgets/                   # Thẻ đồng hồ Gauge, Card thông số, Biểu đồ
├── assets/                            # Biểu tượng thời tiết, hình ảnh minh họa
└── pubspec.yaml                       # Khai báo dependencies
```

---

## 🛠️ Hướng dẫn Khởi tạo Dự án
Khi máy tính đã cài đặt Flutter SDK, mở terminal tại thư mục này và chạy các lệnh:

```bash
# 1. Khởi tạo khung dự án Flutter
flutter create --org com.adht .

# 2. Cài đặt các gói thư viện cần thiết
flutter pub add mqtt_client supabase_flutter fl_chart provider intl

# 3. Chạy ứng dụng trên máy ảo hoặc thiết bị thật
flutter run
```
