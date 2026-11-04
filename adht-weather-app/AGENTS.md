# Hướng Dẫn Dành Cho AI Agent (AGENTS.md)

Tài liệu này quy định các nguyên tắc, chuẩn mực kiến trúc, và quy ước phát triển mà mọi AI Agent phải tuân thủ nghiêm ngặt khi đọc, sửa đổi hoặc sinh mã nguồn trong kho lưu trữ **Weather Monitoring App**.

---

## 1. Bối Cảnh Dự Án (Project Context)

- **Mục đích**: Ứng dụng di động đa nền tảng (**Android** và **iOS**) hiển thị trực quan dữ liệu từ trạm quan trắc thời tiết IoT.
- **Công nghệ cốt lõi**: **Flutter 3.x** & **Dart 3.x**.
- **4 Thông số cảm biến đo lường duy nhất**:
  1. `Nhiệt độ (Temperature)`: Đơn vị `°C`
  2. `Độ ẩm (Humidity)`: Đơn vị `%`
  3. `Lượng mưa (Rainfall)`: Đơn vị `mm`
  4. `Tốc độ gió (Wind Speed)`: Đơn vị `km/h`
- **3 Khung nhìn thời gian chính**:
  1. **Hiện tại (Current)**: Bản ghi đo đạc mới nhất.
  2. **Trong ngày (Intra-day)**: Chuỗi dữ liệu từ `00:00` sáng đến hiện tại với độ chi tiết mốc tối đa **5 phút/lần đo**.
  3. **7 ngày gần nhất (7-Day History)**: Biểu diễn giá trị **trung bình ngày** (Avg Temp, Avg Humidity, Avg Wind Speed) và tổng lượng mưa ngày.

---

## 2. Quy Tắc Kiến Trúc & Thiết Kế Bắt Buộc (Core Architectural Rules)

### 2.1. Chiến lược Phát triển UI-First & Mock-Driven
- Khi chưa có tài liệu API chính thức từ phía backend: **Ưu tiên hoàn thiện toàn bộ khung giao diện (UI/UX), biểu đồ và tương tác**.
- Dữ liệu được cấp phát thông qua `MockWeatherRepository` với bộ sinh số liệu mốc 5 phút và 7 ngày chân thực.
- Phân tách rạch ròi giữa Views và Data qua Repository Pattern: Khi có API thật, chỉ thay thế nguồn dữ liệu ở tầng Data mà không chạm vào tầng UI.

### 2.2. Cơ chế Làm mới Dữ liệu (Update Strategy)
- **CHỈ SỬ DỤNG PULL-TO-REFRESH**: Người dùng vuốt màn hình xuống để làm mới.
- **TUYỆT ĐỐI KHÔNG DÙNG POLLING NGẦM**: Không tạo `Timer.periodic`, không polling HTTP liên tục để bảo tồn pin thiết bị.

### 2.3. Cơ sở Dữ liệu Cục bộ SQLite (Offline-First 7 Ngày)
- Tích hợp **`sqflite`** để lưu trữ lịch sử 7 ngày gần nhất ngay trên thiết bị.
- Luôn ưu tiên hiển thị dữ liệu từ SQLite ngay khi mở app (< 0.2s).
- Khi có mạng và vuốt refresh thành công: Lưu dữ liệu mới và tự động thực thi dọn dẹp: `DELETE FROM weather_readings WHERE timestamp < [now - 7 days]`.
- Khi mất mạng: Giữ nguyên dữ liệu SQLite và hiển thị thông báo nhẹ (Offline banner), không để sập ứng dụng.

---

## 3. Quy Ước Cấu Trúc Thư Mục (`lib/`)

Mọi tệp mã nguồn mới bắt buộc phải đặt đúng vị trí theo cấu trúc sau:

```
lib/
├── core/
│   ├── constants/        # Hằng số, màu sắc, kích thước lề 8-pt
│   ├── theme/            # Material 3 AppTheme (Light & Dark)
│   └── utils/            # Format thời gian mốc 5p (HH:mm), đơn vị đo
├── data/
│   ├── database/         # SQLite setup, weather_dao.dart, migrations
│   ├── mock/             # Bộ sinh dữ liệu giả lập mốc 5p và 7 ngày
│   ├── models/           # WeatherCurrentModel, WeatherPoint5m, DailySummary
│   ├── network/          # Dio HTTP client, api_service, error interceptor
│   └── repositories/     # WeatherRepository interface & implementations
├── providers/            # Riverpod StateNotifiers & UI states
├── views/
│   ├── screens/          # Các màn hình chính (Dashboard, IntraDay, History7d, Settings)
│   └── widgets/          # Widgets tái sử dụng (Common, Current, Charts)
└── main.dart             # Điểm khởi chạy ứng dụng
```

---

## 4. Chuẩn Mực Lập Trình & Giao Diện (Coding & UI Standards)

- **Ngôn ngữ thiết kế**: Material 3 (`useMaterial3: true`). Hỗ trợ cả **Light Mode** và **Dark Mode**.
- **Biểu đồ**: Luôn sử dụng thư viện **`fl_chart`**. Đảm bảo trục X mốc 5 phút không bị đè chữ (đánh dấu nhãn mỗi 3 giờ, chạm tay hiện Tooltip mốc 5 phút).
- **Quản lý trạng thái**: Sử dụng **`flutter_riverpod`** (v2.x) kết hợp `AsyncValue`.
- **Hệ thống khoảng cách (Spacing)**: Sử dụng lưới 8 điểm (8dp, 16dp, 24dp, 32dp).
- **Tối ưu Widget**:
  - Dùng `const` constructors cho tất cả các widget tĩnh.
  - Phương thức `build()` phải ngắn gọn (< 80 dòng); tách các khối phức tạp thành widget riêng biệt trong `views/widgets/`.
  - Luôn bọc `RepaintBoundary` quanh các biểu đồ `fl_chart` để đạt 60fps mượt mà.

---

## 5. Tài Liệu Dự Án Tham Chiếu (Reference Documents)

Mọi thay đổi lớn cần đối chiếu với các tài liệu kỹ thuật đã được phê duyệt trong thư mục `docs/`:
- [Project Overview](file:///E:/WeatherMonitoringApp/weather_monitoring/docs/plan/Project_overview.md): Tầm nhìn dự án và lộ trình phát triển.
- [Feature List](file:///E:/WeatherMonitoringApp/weather_monitoring/docs/plan/feature_list.md): Chi tiết chức năng và các trường hợp ngoại lệ.
- [Architecture](file:///E:/WeatherMonitoringApp/weather_monitoring/docs/architecture/architecture.md): Sơ đồ phân tầng và thiết kế CSDL SQLite.
- [Data Flow](file:///E:/WeatherMonitoringApp/weather_monitoring/docs/architecture/data_flow.md): Sơ đồ tuần tự và chuẩn hóa dữ liệu đồ thị.
- [Tech Stack](file:///E:/WeatherMonitoringApp/weather_monitoring/docs/architecture/tech_stack.md): Danh mục thư viện và Design Tokens.
