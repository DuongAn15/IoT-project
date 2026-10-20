# 📱 ADHT Weather Station - Mobile Application

Ứng dụng di động đa nền tảng (Android & iOS) thuộc hệ sinh thái **Trạm quan trắc thời tiết thông minh ADHT**.

---

## 🚀 Công nghệ sử dụng
- **Framework**: [Flutter](https://flutter.dev/) (Dart SDK)
- **Giao thức thời gian thực**: MQTT qua WebSocket (`wss://`) kết nối với **EMQX Cloud Serverless**
- **Cơ sở dữ liệu & Phân tích lịch sử**: **Supabase Cloud** (PostgreSQL REST API)
- **Thư viện biểu đồ**: `fl_chart` (Vẽ biểu đồ đường cong nhiệt độ, độ ẩm và biểu đồ cột lượng mưa)
- **Quản lý trạng thái (State Management)**: `provider`

---

## 📂 Kiến trúc Thư mục Dự kiến
```text
adht-weather-app/
├── lib/
│   ├── main.dart                      # Điểm khởi chạy ứng dụng
│   ├── core/                          # Hằng số (EMQX/Supabase API), Theme, Helpers
│   ├── data/
│   │   ├── models/                    # Model dữ liệu thời tiết & cấu hình
│   │   └── services/                  # MqttService & SupabaseService
│   └── presentation/
│       ├── providers/                 # WeatherProvider (quản lý state phản ứng)
│       ├── screens/
│       │   ├── dashboard_screen.dart  # Màn hình số đo thời gian thực & trạng thái Online
│       │   ├── analytics_screen.dart  # Màn hình biểu đồ phân tích 6h, 24h, 7 ngày
│       │   └── control_screen.dart    # Màn hình điều khiển còi & cài đặt ngưỡng
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
