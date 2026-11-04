# Danh Sách Tính Năng & Yêu Cầu Chi Tiết (Feature List & Requirements)

> **Dự án**: Weather Monitoring Mobile App  
> **Tài liệu**: Chi tiết tính năng người dùng, tiêu chí chấp nhận (Acceptance Criteria), và xử lý trường hợp đặc biệt (Edge Cases).

---

## 1. Tổng Quan Hệ Thống Tính Năng (Feature Overview Matrix)

| Mã tính năng | Tên tính năng | Mức độ ưu tiên | Trạng thái triển khai |
|---|---|---|---|
| **FEAT-01** | Dashboard Thời tiết Hiện tại (Current Weather Overview) | P0 (Bắt buộc) | Sprint 1 (Khung UI Mock) |
| **FEAT-02** | Phân tích Diễn biến Trong ngày (5-Minute Intra-Day Charts) | P0 (Bắt buộc) | Sprint 1 (Khung UI Mock) |
| **FEAT-03** | Phân tích Xu hướng 7 Ngày Gần nhất (7-Day Daily Averages) | P0 (Bắt buộc) | Sprint 1 (Khung UI Mock) |
| **FEAT-04** | Cơ chế Vuốt Làm mới (Native Pull-to-refresh) | P0 (Bắt buộc) | Sprint 1 (Khung UI Mock) |
| **FEAT-05** | Lưu trữ Ngoại tuyến 7 Ngày bằng SQLite (Offline-First Cache) | P1 (Cao) | Sprint 2 (SQLite Integration) |
| **FEAT-06** | Bộ chuyển đổi Giao diện Sáng / Tối (Light & Dark Mode) | P1 (Cao) | Sprint 1 (Theme Setup) |
| **FEAT-07** | Màn hình Cài đặt Kết nối Trạm Đo (Station & API Settings) | P2 (Trung bình) | Sprint 3 (Settings View) |

---

## 2. Chi Tiết Từng Tính Năng

---

### FEAT-01: Dashboard Thời tiết Hiện tại (Current Weather Overview)

#### 1. Mô tả tính năng
Màn hình trung tâm mở ra khi người dùng vào ứng dụng. Cung cấp cái nhìn tức thì về trạng thái thời tiết tại trạm đo với 4 thông số cảm biến cốt lõi: Nhiệt độ, Độ ẩm, Lượng mưa, Tốc độ gió.

#### 2. Các thành phần giao diện (UI Components)
1. **Header Trạm Đo (App Station Header)**:
   - Tên trạm giám sát (ví dụ: *"Trạm Khí Tượng IoT #01"*).
   - Nhãn thời gian cập nhật gần nhất (`Cập nhật: 14:25 hôm nay`).
   - Nút lối tắt đến màn hình cài đặt trạm.
2. **Thẻ Anh Hùng Thời Tiết (Hero Weather Card)**:
   - Hiển thị nhiệt độ lớn và nổi bật nhất (`28.5°C`).
   - Đánh giá trạng thái thời tiết tổng quan (ví dụ: *"Thời tiết mát mẻ"*, *"Mưa nhẹ"*, *"Gió giật"*).
   - Nền thẻ sử dụng gradient mềm mại biến đổi nhẹ theo nhiệt độ và trạng thái môi trường.
3. **Lưới 4 Chỉ Số Cảm Biến (Metric Grid - 2x2)**:
   - **Ô Nhiệt độ (Temperature)**: Biểu tượng nhiệt kế, hiển thị giá trị (°C), thanh màu nhiệt độ (Xanh mát -> Cam ấm -> Đỏ nóng).
   - **Ô Độ ẩm (Humidity)**: Biểu tượng giọt sương, hiển thị phần trăm (%), thang đánh giá (Khô ráo / Dễ chịu / Ẩm ướt).
   - **Ô Lượng mưa (Rainfall)**: Biểu tượng đám mây mưa, hiển thị lượng mưa tích lũy gần nhất (mm).
   - **Ô Tốc độ gió (Wind Speed)**: Biểu tượng cối xay gió / làn gió, hiển thị tốc độ (km/h) kèm cấp gió Beaufort ước lượng.

#### 3. Tiêu chí chấp nhận (Acceptance Criteria)
- [x] Hiển thị đầy đủ cả 4 thông số không bị che khuất trên màn hình từ nhỏ (iPhone SE, màn hình 4.7 inch) đến lớn (màn hình > 6.7 inch).
- [x] Đơn vị đo được gắn nhãn chuẩn xác (°C, %, mm, km/h).
- [x] Chạm vào từng ô chỉ số có thể dẫn trực tiếp đến biểu đồ tương ứng của chỉ số đó.

---

### FEAT-02: Phân tích Diễn biến Trong ngày (5-Minute Intra-Day Charts)

#### 1. Mô tả tính năng
Trực quan hóa toàn bộ chuỗi số liệu từ thời điểm `00:00` sáng đến thời điểm hiện tại của ngày hôm đó. Độ phân giải dữ liệu hiển thị chi tiết tối đa tới **từng mốc 5 phút/lần đo**.

#### 2. Các thành phần giao diện & Biểu đồ
1. **Biểu đồ Đường Mượt mà (Spline Line Chart)** cho **Nhiệt độ & Độ ẩm**:
   - Trục Tung (Y-axis): Thang đo nhiệt độ (°C) hoặc độ ẩm (%).
   - Trục Hoành (X-axis): Trục thời gian từ 00:00 đến thời điểm hiện tại. Đánh dấu mốc giờ mỗi 2-3 tiếng (00:00, 03:00, 06:00, 09:00, 12:00, 15:00, 18:00, 21:00) để chống chồng lấn chữ.
   - Đường biểu diễn bo cong mềm mại (Curved Line) kết hợp vùng đổ bóng gradient bên dưới (Gradient Fill) tạo chiều sâu.
2. **Biểu đồ Cột Lượng Mưa (Rainfall Bar Chart)**:
   - Thể hiện sự xuất hiện của các cơn mưa trong ngày theo từng mốc thời gian.
3. **Thanh Chuyển Đổi Chỉ Số (Metric Tab Selector)**:
   - Người dùng bấm chuyển nhanh giữa: `Nhiệt độ` | `Độ ẩm` | `Lượng mưa` | `Tốc độ gió`.
4. **Tương tác Chạm Thông Minh (Interactive Touch Tooltip)**:
   - Khi người dùng chạm ngón tay và kéo dọc biểu đồ, xuất hiện đường gióng chỉ vị trí (Crosshair indicator) và hộp thông tin nổi (Tooltip) hiển thị:
     - Giờ phút chính xác của mốc 5 phút (Ví dụ: `09:35`).
     - Giá trị đo đạc tương ứng (Ví dụ: `Nhiệt độ: 31.2°C`).

#### 3. Tiêu chí chấp nhận (Acceptance Criteria)
- [x] Biểu đồ tự động giới hạn trục X dừng lại đúng thời điểm hiện tại của ngày (không hiển thị dữ liệu tương lai).
- [x] Tương tác vuốt chạm đạt tốc độ khung hình ổn định 60fps, không gây giật lag kể cả khi có đủ 288 điểm đo trong ngày.
- [x] Tooltip tự động căn chỉnh vị trí thông minh để không bị khuất khỏi viền màn hình điện thoại.

---

### FEAT-03: Phân tích Xu hướng 7 Ngày Gần nhất (7-Day Daily Averages)

#### 1. Mô tả tính năng
Cung cấp cái nhìn bao quát về chu kỳ thời tiết trong 7 ngày gần nhất (bao gồm hôm nay và 6 ngày trước đó). Để biểu diễn đại diện chính xác cho từng ngày, hệ thống tính toán **giá trị trung bình ngày (Daily Average)** đối với Nhiệt độ, Độ ẩm, Tốc độ gió, và **tổng tích lũy ngày (Daily Sum)** đối với Lượng mưa.

#### 2. Các thành phần giao diện & Biểu đồ
1. **Bảng Tóm Tắt Tuần (Weekly Summary Ribbon)**:
   - Hiển thị danh sách 7 ngày (ví dụ: *T2, T3, T4, T5, T6, T7, CN*).
   - Mỗi ngày hiển thị icon thời tiết đại diện và nhiệt độ trung bình.
2. **Biểu đồ Cột So Sánh 7 Ngày (7-Day Bar / Column Chart)**:
   - Trục X: 7 cột tương ứng 7 ngày gần nhất. Cột ngày hôm nay được làm nổi bật với màu viền riêng biệt.
   - Trục Y: Giá trị trung bình của chỉ số được chọn.
   - Chạm vào từng cột hiển thị Tooltip: Ngày đo, Giá trị trung bình, Giá trị thấp nhất (Min) và cao nhất (Max) trong ngày.
3. **Biểu đồ Tổng Lượng Mưa 7 Ngày**:
   - Biểu diễn tổng lượng mưa của từng ngày (mm/ngày), giúp phát hiện ngày mưa lớn nhất trong tuần.

#### 3. Tiêu chí chấp nhận (Acceptance Criteria)
- [x] Hiển thị chính xác 7 cột đại diện cho 7 ngày tính ngược từ hôm nay.
- [x] Công thức tính toán trung bình ngày hoạt động chính xác từ tập dữ liệu bản ghi.
- [x] Cho phép người dùng chuyển đổi qua lại giữa các chỉ số bằng cử chỉ vuốt ngang hoặc bấm tab.

---

### FEAT-04: Cơ Chế Vuốt Làm Mới (Pull-to-Refresh)

#### 1. Mô tả tính năng
Ứng dụng không chạy polling ngầm liên tục qua mạng để bảo tồn pin thiết bị. Thay vào đó, người dùng chủ động kéo nhẹ màn hình từ trên xuống để làm mới dữ liệu.

#### 2. Kịch bản vận hành
1. Người dùng kéo màn hình xuống tại bất kỳ vị trí nào trên Dashboard.
2. Xuất hiện con quay tải dữ liệu thích ứng (Adaptive Spinner: Cupertino Activity Indicator trên iOS, Material Circular Indicator trên Android).
3. Ứng dụng kích hoạt quá trình nạp dữ liệu mới.
4. Khi hoàn thành: Con quay biến mất, các thẻ chỉ số và biểu đồ cập nhật giá trị mới với hiệu ứng mờ dần nhẹ (Fade transition), dòng chữ `Cập nhật lúc ...` được cập nhật sang giờ phút hiện tại.

#### 3. Tiêu chí chấp nhận (Acceptance Criteria)
- [x] Cử chỉ vuốt tự nhiên, không bị xung đột với thao tác vuốt cuộn màn hình hoặc vuốt ngang trên biểu đồ.
- [x] Phản hồi xúc giác nhẹ (Haptic feedback) khi kéo đủ ngưỡng làm mới.

---

### FEAT-05: Lưu Trữ Ngoại Tuyến 7 Ngày Bằng SQLite (Offline-First Cache)

#### 1. Mô tả tính năng
Tích hợp cơ sở dữ liệu SQLite nhẹ (`sqflite`) lưu giữ trọn vẹn lịch sử đo đạc của 7 ngày gần nhất trên bộ nhớ máy.

#### 2. Kịch bản vận hành
1. **Khi mở ứng dụng**: Ứng dụng đọc ngay dữ liệu từ SQLite nội bộ và vẽ giao diện lập tức (thời gian hiển thị dưới 0.2 giây, không có màn hình trắng).
2. **Khi có mạng và vuốt refresh**: Ứng dụng lấy dữ liệu mới từ backend, chèn/cập nhật vào SQLite, đồng thời tự động xóa các bản ghi cũ hơn 7 ngày (`timestamp < now - 7 days`).
3. **Khi mất kết nối mạng**: Ứng dụng giữ nguyên dữ liệu đã lưu trong SQLite, hiển thị một biểu ngữ nhỏ (Offline Banner): *"Chế độ ngoại tuyến. Dữ liệu lưu lúc HH:mm DD/MM"*. Người dùng vẫn tự do xem biểu đồ 5 phút và biểu đồ 7 ngày bình thường.

---

### FEAT-06: Chế Độ Giao Diện Sáng / Tối (Light & Dark Mode)

#### 1. Mô tả tính năng
Hỗ trợ đầy đủ 2 giao diện Sáng và Tối theo tiêu chuẩn Material 3:
- **Light Mode**: Phông nền trắng ngà dịu mắt (`#F8FAFC`), thẻ màu trắng (`#FFFFFF`), chữ xanh đen đậm (`#1E293B`), biểu đồ đường màu xanh da trời sắc nét (`#0284C7`).
- **Dark Mode**: Phông nền đen công nghệ (`#0F172A`), thẻ bề mặt tối (`#1E293B`), chữ trắng kem tương phản cao (`#F8FAFC`), biểu đồ phát sáng neon nhẹ (`#38BDF8`).

#### 2. Tùy chọn cài đặt
- Tự động theo hệ điều hành (System Default).
- Luôn bật chế độ Sáng (Always Light).
- Luôn bật chế độ Tối (Always Dark).

---

## 3. Xử Lý Các Trường Hợp Ngoại Lệ (Edge Cases & Error Handling)

| Tình huống ngoại lệ (Edge Case) | Hành vi ứng dụng (App Behavior) |
|---|---|
| **Mất kết nối mạng khi vuốt refresh** | Không báo lỗi tràn màn hình. Hiển thị Snackbar hoặc Offline Banner thông báo: *"Không thể kết nối máy chủ. Đang hiển thị bản tin gần nhất"*. Dữ liệu cũ trên màn hình được giữ nguyên. |
| **Cảm biến bị lỗi/mất mẫu đo (Missing Data)** | Biểu đồ nội suy đường nối mượt mà hoặc thể hiện khoảng đứt nét nhẹ, không làm sập ứng dụng. |
| **Chưa có đủ dữ liệu trong ngày (Ví dụ: Lúc 00:15 sáng)** | Trục X chỉ vẽ từ 00:00 đến 00:15, các mốc thời gian còn lại hiển thị dạng chờ; biểu đồ tự điều chỉnh độ rộng hiển thị phù hợp. |
| **Xoay ngang màn hình (Orientation Change)** | Khóa mặc định hướng dọc (Portrait) trên điện thoại để mang lại trải nghiệm xem dashboard tốt nhất; màn hình biểu đồ chi tiết hỗ trợ nút phóng to toàn màn hình nếu cần phân tích kỹ. |
