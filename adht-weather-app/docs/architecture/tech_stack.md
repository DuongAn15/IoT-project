# Công Nghệ, Thư Viện & Hệ Thống Thiết Kế (Tech Stack & Design System)

> **Dự án**: Weather Monitoring Mobile App  
> **Tài liệu**: Quy chuẩn công nghệ, danh mục thư viện mã nguồn mở, hệ thống tokens thiết kế (Design Tokens) và cấu hình dự án.

---

## 1. Nền Tảng & Ngôn Ngữ (Platform & Framework)

| Thành phần | Phiên bản | Ghi chú |
|---|---|---|
| **Flutter SDK** | `>= 3.13.0 < 4.0.0` | Đa nền tảng di động Android và iOS. |
| **Dart SDK** | `^3.13.0` | Hỗ trợ đầy đủ Null Safety, Records & Pattern Matching. |
| **Hệ điều hành Android** | `minSdkVersion: 21` (Android 5.0+) | Phủ sóng > 98% thiết bị Android đang hoạt động. |
| **Hệ điều hành iOS** | `iOS 12.0+` | Tương thích mọi dòng iPhone từ iPhone 6s trở lên. |

---

## 2. Danh Mục Thư Viện Mã Nguồn Mở (Dependencies Breakdown)

Hệ thống thư viện được tuyển chọn theo các tiêu chí: Ổn định cao, cộng đồng lớn, hỗ trợ cập nhật lâu dài và hiệu năng mượt mà.

### 2.1. Thư viện Trực quan hóa & Đồ thị
- **`fl_chart: ^0.70.0`**: Thư viện biểu đồ số 1 cho Flutter. Hỗ trợ biểu đồ đường cong mượt mà (`LineChart`), biểu đồ cột (`BarChart`), hiệu ứng đổi màu Gradient và hệ thống cảm ứng (Touch callback / Tooltip) hiệu năng cao.

### 2.2. Thư viện Quản lý Trạng thái & Kiến trúc
- **`flutter_riverpod: ^2.6.1`**: Giải pháp quản lý trạng thái hiện đại, không phụ thuộc `BuildContext`, hỗ trợ kiểm thử dễ dàng, cơ chế hủy (Auto-dispose) và xử lý bất đồng bộ `AsyncValue` hoàn hảo.

### 2.3. Thư viện Lưu trữ Ngoại tuyến (Offline-First SQLite)
- **`sqflite: ^2.4.1`**: Thư viện cơ sở dữ liệu SQLite chính thống cho Flutter trên Android và iOS.
- **`path_provider: ^2.1.5`**: Xác định đường dẫn thư mục lưu trữ an toàn trên thiết bị (Application Documents Directory).
- **`path: ^1.9.0`**: Thao tác nối đường dẫn tệp CSDL SQLite chuẩn xác trên từng nền tảng.

### 2.4. Thư viện Mạng & Tiện ích Dữ liệu
- **`dio: ^5.7.0`**: Client HTTP mạnh mẽ, hỗ trợ cấu hình Timeout (10 giây), Base URL linh hoạt, tự động parse JSON và cơ chế bắt lỗi mạng (Interceptors).
- **`intl: ^0.19.0`**: Xử lý định dạng thời gian mốc 5 phút (`HH:mm`), định dạng ngày tháng (`dd/MM/yyyy`) và định dạng số thập phân.

### 2.5. Giao diện & Trải nghiệm Người dùng (UI/UX)
- **`google_fonts: ^6.2.1`**: Nhúng phông chữ chất lượng cao (Inter & Outfit) mang lại tính thẩm mỹ cao cấp.
- **`shimmer: ^3.0.0`**: Hiệu ứng khung xương tải dữ liệu (Skeleton loading) khi người dùng mở app hoặc vuốt refresh.

---

## 3. Bản Mẫu Cấu Hình `pubspec.yaml` Chuẩn

```yaml
name: weather_monitoring
description: "Cross-platform Weather Monitoring Mobile Application with interactive charts and offline SQLite cache."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: ^3.13.7

dependencies:
  flutter:
    sdk: flutter
  
  # State Management
  flutter_riverpod: ^2.6.1
  
  # Charts & Visualization
  fl_chart: ^0.70.0
  
  # Local SQLite Database (7-Day Offline Cache)
  sqflite: ^2.4.1
  path_provider: ^2.1.5
  path: ^1.9.0
  
  # Networking & HTTP
  dio: ^5.7.0
  
  # UI, Fonts & Effects
  google_fonts: ^6.2.1
  shimmer: ^3.0.0
  intl: ^0.19.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0

flutter:
  uses-material-design: true
```

---

## 4. Hệ Thống Thiết Kế (Design System & Tokens)

Dựa trên hướng dẫn từ chuyên gia `flutter-ai-ui-skill`, ứng dụng sử dụng bộ nhận diện màu sắc chuyên dụng cho lĩnh vực Thời tiết & Giám sát Môi trường (Weather Dashboard Palette).

### 4.1. Bảng Màu Thương Hiệu (Brand & Surface Tokens)

| Token Tên gọi | Mã Hex (Light Mode) | Mã Hex (Dark Mode) | Ứng dụng thực tế |
|---|---|---|---|
| **Primary Color** | `#0369A1` (Ocean Blue) | `#38BDF8` (Sky Glow) | Thanh Header, điểm nhấn thương hiệu, nút chính. |
| **Secondary Color** | `#0EA5E9` (Sky Blue) | `#0284C7` (Deep Sky) | Thẻ tóm tắt thời tiết, màu viền thẻ đang chọn. |
| **Accent / Sun CTA** | `#F59E0B` (Amber Sun) | `#FBBF24` (Warm Gold) | Huy hiệu trạng thái, chỉ báo nhiệt độ ấm, nút nổi bật. |
| **Background** | `#F8FAFC` (Slate Light) | `#0B1120` (Dark Space) | Phông nền toàn bộ màn hình ứng dụng. |
| **Surface Card** | `#FFFFFF` (Pure White) | `#1E293B` (Dark Card) | Các thẻ chỉ số cảm biến, khung bao quanh biểu đồ. |
| **Text Primary** | `#0F172A` (Deep Slate) | `#F8FAFC` (Clean White) | Số liệu nhiệt độ lớn, tiêu đề màn hình. |
| **Text Secondary** | `#64748B` (Muted Slate) | `#94A3B8` (Soft Slate) | Nhãn đơn vị đo, thời gian cập nhật `HH:mm`. |

### 4.2. Bảng Màu Ngữ Nghĩa Cho 4 Chỉ Số Cảm Biến (Metric Semantic Tokens)

Mỗi thông số được gán một dải màu riêng biệt giúp người dùng nhận diện ngay lập tức mà không cần đọc chữ:

```
[Nhiệt độ (Temperature)]  ──> #EF4444 (Đỏ ấm / Cam nhiệt)
[Độ ẩm (Humidity)]        ──> #0284C7 (Xanh lam nước)
[Lượng mưa (Rainfall)]    ──> #06B6D4 (Xanh mây mưa / Cyan)
[Tốc độ gió (Wind Speed)] ──> #10B981 (Xanh lục ngọc)
```

---

## 5. Quy Chuẩn Kiểu Chữ (Typography Hierarchy)

Sử dụng phông chữ **`Inter`** kết hợp **`Outfit`** thông qua `google_fonts`:

```dart
// Ví dụ cấu hình TextTheme chuẩn trong theme
final textTheme = TextTheme(
  // Hiển thị số đo nhiệt độ cực đại trên Hero Card (ví dụ 28.5°)
  displayLarge: GoogleFonts.outfit(
    fontSize: 48,
    fontWeight: FontWeight.bold,
    letterSpacing: -1.0,
  ),
  // Tiêu đề các phần (Biểu đồ trong ngày, Xu hướng 7 ngày)
  titleLarge: GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  ),
  // Số đo trong 4 ô cảm biến (2x2 Grid)
  headlineSmall: GoogleFonts.outfit(
    fontSize: 22,
    fontWeight: FontWeight.w700,
  ),
  // Nhãn tên thông số và mô tả
  bodyMedium: GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
  ),
  // Nhãn trục biểu đồ và Tooltip mốc 5 phút
  labelSmall: GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
  ),
);
```

---

## 6. Hệ Thống Khoảng Cách & Bo Góc (Spacing & Radii)

- **Quy tắc lưới 8 điểm (8-Point Grid)**:
  - `xs`: 4dp (Khoảng cách giữa icon và chữ nhỏ).
  - `sm`: 8dp (Khoảng cách giữa các phần tử nội bộ trong thẻ).
  - `md`: 16dp (Khoảng cách lề màn hình tiêu chuẩn, khoảng cách giữa các thẻ).
  - `lg`: 24dp (Khoảng cách giữa các phân đoạn nội dung lớn).
  - `xl`: 32dp (Khoảng cách đỉnh trang).
- **Bo góc thẻ (Border Radius)**:
  - Thẻ Hero Card: `24dp` (Bo tròn hiện đại, tạo cảm giác thân thiện).
  - Thẻ 4 ô cảm biến & Khung Biểu đồ: `16dp`.
  - Tooltip trên đồ thị: `8dp`.

---

## 7. Tiêu Chuẩn Hiệu Năng & Chuyển Động (Performance & Animation)

1. **Chuẩn 60fps khi tương tác đồ thị**: Bọc các thành phần biểu đồ phức tạp bằng `RepaintBoundary` để hạn chế việc vẽ lại toàn màn hình khi người dùng chạm rê tay trên trục thời gian.
2. **Thời lượng hiệu ứng (Duration)**:
   - Hiệu ứng xuất hiện dữ liệu / chuyển đổi Tab: `300ms` với `Curves.easeInOut`.
   - Hiệu ứng khung xương Shimmer: Chu kỳ lặp `1500ms`.
3. **Thân thiện với Pin thiết bị**: Tuyệt đối không sử dụng `Timer.periodic` chạy ngầm. Mọi kết nối chỉ kích hoạt khi người dùng thực hiện thao tác vuốt làm mới (Pull-to-refresh).
