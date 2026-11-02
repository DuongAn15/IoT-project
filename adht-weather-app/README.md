# 📱 ADHT Weather Station - Mobile Application & Web Dashboard

Ứng dụng đa nền tảng (Android, iOS & Web) thuộc hệ sinh thái **Trạm quan trắc thời tiết thông minh ADHT**.

Ứng dụng kết nối **DUY NHẤT với Backend Gateway** (Mô hình bảo mật Single Gateway - không lộ Database Key):
1. **Giám sát thời gian thực (Realtime Dashboard)**: Lắng nghe kênh **WebSocket** từ Backend để cập nhật số đo nhiệt độ, độ ẩm, gió, mưa mỗi 5 giây.
2. **Biểu đồ & Phân tích lịch sử (Historical Analytics)**: Gọi **REST API** Backend để vẽ biểu đồ diễn biến thời tiết 1H, 6H, 24H, 3D, 7D đã được làm mịn (Downsampled) bằng thư viện `fl_chart`.
3. **Điều khiển & Cài đặt từ xa (Remote Control)**: Gọi **REST API** Backend để gửi lệnh bật còi, đổi LED, reboot trạm và cập nhật ngưỡng cảnh báo NVS.
4. **Nhận Cảnh Báo Sớm Khẩn Cấp (Firebase FCM)**: Tích hợp **Firebase Cloud Messaging** để rung chuông và hiện banner cảnh báo đỏ trên màn hình khóa khi có giông bão, mưa to kể cả khi tắt App.

---

## 🚀 Công nghệ sử dụng
- **Framework**: [Flutter](https://flutter.dev/) (Dart SDK - Hỗ trợ Mobile & Web)
- **Giao thức mạng**: REST API (`dio`) + Realtime (`web_socket_channel`) kết nối trực tiếp với **Backend Gateway**
- **Thông báo đẩy (Push Alerts)**: **Firebase Cloud Messaging (FCM)**
- **Thư viện biểu đồ**: `fl_chart` (Vẽ biểu đồ đường cong nhiệt độ, độ ẩm và biểu đồ cột lượng mưa)
- **Quản lý trạng thái (State Management)**: `provider`

---

## 📂 Kiến trúc Thư mục Clean Architecture
```text
adht-weather-app/
├── lib/
│   ├── main.dart                      # Điểm khởi chạy ứng dụng
│   ├── core/                          # Hằng số Base URL Backend, Theme, Helpers
│   ├── data/
│   │   ├── models/                    # Model dữ liệu thời tiết & cấu hình
│   │   └── services/                  # ApiClientService, WebSocketService & FcmService
│   └── presentation/
│       ├── providers/                 # WeatherProvider (quản lý state phản ứng)
│       ├── screens/
│       │   ├── dashboard_screen.dart  # Màn hình số đo thời gian thực qua WebSocket
│       │   ├── analytics_screen.dart  # Màn hình biểu đồ phân tích 1H, 6H, 24H, 3D, 7D
│       │   ├── forecast_screen.dart   # Màn hình dự báo thời tiết 3 ngày tới
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
