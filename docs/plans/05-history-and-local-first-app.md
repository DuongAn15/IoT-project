# P05 — Lịch sử thời tiết và app ưu tiên dữ liệu cục bộ

**Trạng thái:** Đang triển khai trên nhánh `feat/p05-history-and-local-first-app`.

## Quyết định sản phẩm

- Mọi thời điểm đo và nhận đều là mốc UTC. **Giờ và ngày hiển thị do điện thoại quyết định**, kể cả khi điện thoại và trạm ở hai nơi khác nhau.
- Vị trí trạm là nhãn địa lý để người dùng biết trạm ở đâu; không dùng vị trí để suy ra múi giờ, căn bucket hoặc biến đổi timestamp. Giao diện ghi rõ “Thời gian: giờ trên thiết bị”.
- `rain_rate` có đơn vị mm/h, `rainfall_mm` là lượng mưa mm. Không cộng các giá trị rate thành tổng mm; legacy amount chỉ được trình bày kèm provenance `estimated` hoặc `unknown`.
- Firmware và backend không cần lưu múi giờ riêng cho mỗi trạm. Tham số `timezone` của API lịch sử chỉ còn để tương thích client cũ; app P05 gửi `UTC`.

## Hợp đồng theo tầng

### Firmware → backend

- Minute log v2 đã đồng bộ đồng hồ gửi `interval_start`/`interval_end` dạng ISO-8601 UTC, với `clock_quality=synchronized`. Khi chưa đồng bộ, gửi giới hạn uptime và `clock_quality=unsynchronized`; backend giữ phân biệt thời điểm đo với thời điểm nhận.
- Giữ `device_id`, `deployment_id`, `boot_id`, `window_sequence` và cùng payload khi retry. Vị trí trạm không nằm trong từng bản tin đo; không cần đổi payload firmware để thực hiện P05 này.
- Rain tip counter, reset epoch, calibration và quality/coverage của P04 tiếp tục là nguồn tính amount, rate và weighted stats.

### Backend → app

- Lưu `recorded_at` và `received_at` dạng UTC. API trả `recorded_at` ISO-8601 UTC; bucket thông thường căn theo UTC, các khoảng thời gian dùng dạng nửa mở `[from,to)`.
- `GET /devices` và `GET /devices/{id}` trả thêm `location` dạng nhãn dễ đọc. Backend đọc `STATION_LOCATIONS` là JSON map `device_id` → nhãn vị trí; ba trạm hiện có có fallback Đà Nẵng. Trạm khác không có cấu hình được hiển thị “Chưa có vị trí trạm”. Không cần cột timezone trong bảng thiết bị hoặc log.
- `GET /weather/history` nhận `from` và `to` UTC do app tính. Với dữ liệu trong ngày, app tính 00:00 theo đồng hồ điện thoại rồi chuyển sang UTC; backend trả các bucket UTC trong khoảng này. `since` là mốc đồng bộ bổ sung, không thay ý nghĩa của khoảng thời gian đo; bản ghi v2 đến muộn được xét cả theo `received_at`.
- Với `range=7d`, app gửi `day_starts`: tám mốc UTC tương ứng đầu bảy ngày local liên tiếp và đầu ngày tiếp theo. Backend tổng hợp riêng mỗi khoảng `[day_starts[i],day_starts[i+1])`, trả mốc UTC đầu ngày cùng amount, rate, thống kê, coverage/provenance/revision. App tải lại đủ 7 ngày mỗi lần refresh để nhận correction và đúng ranh giới ngày hiện tại.
- Backend vẫn nhận tham số `timezone` cũ trong giai đoạn tương thích. Không dùng múi giờ trạm cho request mới của app.

### App

- Lưu timestamp đo UTC vào SQLite/file cache. Chuyển timestamp sang `DateTime` local của điện thoại lúc hiển thị, lọc “hôm nay” và tạo nhãn ngày; không dùng bảng offset hoặc quy tắc múi giờ trạm viết tay.
- Catalogue chứa ID, tên, MAC và nhãn vị trí trạm. Hiển thị vị trí và nhãn “giờ trên thiết bị” tách biệt với số đo. Catalogue cũ thiếu `location` dùng fallback cho ba trạm đã biết.
- Cache trong ngày và cursor gắn với ID trạm, chuỗi dữ liệu, resolution và phiên bản schema; không gắn với timezone trạm. Cache 7 ngày lưu kết quả theo mốc UTC đầu ngày. Khi ranh giới ngày của điện thoại đổi, chỉ dùng những tổng hợp có mốc UTC khớp; không đổi nhãn để giả vờ chúng là dữ liệu cho ngày mới. Cache hourly cũ có thể dùng làm fallback offline.
- SQLite v5 trên cài đặt mới không tạo cột timezone. Nâng cấp v3/v4 giữ hàng đo cũ và cột legacy nếu đã tồn tại; code mới không ghi/đọc cột đó. Chỉ thay cache 7 ngày sau khi request thành công, trong cùng transaction; lỗi mạng giữ nguyên cache đang có.
- Một lần refresh chỉ thực hiện một bộ request cho trạm đã chọn; response trạm cũ không ghi đè UI/cache trạm mới. Không polling nền.

## Thứ tự triển khai và tương thích

1. Giữ nguyên hợp đồng UTC/quality hiện có của firmware P04; xác nhận fixture đồng bộ và chưa đồng bộ.
2. Triển khai backend đọc vị trí trạm và nhận `from`/`to`/`day_starts`; giữ contract `timezone` cũ cho client chưa nâng cấp.
3. Phát hành app dùng giờ điện thoại, nhãn vị trí và cache UTC v5. Nâng cấp SQLite không xóa dữ liệu đo; catalogue cũ vẫn đọc được offline.
4. Sau khi app mới ổn định mới xem xét bỏ nhánh API tương thích cũ; không drop cột legacy chỉ để làm sạch schema trong đợt này.

## Nghiệm thu

- Cùng timestamp UTC hiển thị theo giờ điện thoại; hai điện thoại ở hai múi giờ có nhãn giờ/ngày khác nhau nhưng số đo giống nhau. Giao diện ghi rõ vị trí trạm và nguồn giờ hiển thị.
- Minute log đồng bộ kết thúc đúng 00:00 local thuộc bucket/ngày trước (khoảng đo nửa mở); log chưa đồng bộ dùng thời điểm nhận. Mẫu sát 00:00 local nằm đúng ngày trên biểu đồ trong ngày và tổng hợp 7 ngày; `rainfall_mm` cộng đúng, `rain_rate` không bị cộng thành amount. Ngày hiện tại, bucket thiếu coverage và ngày có cả v1 trước cutover lẫn v2 sau cutover được đánh dấu partial trong API; app hiển thị rõ “Ngày chuyển đổi v1 → v2 · Dữ liệu một phần”.
- Bản ghi đến muộn hoặc correction cập nhật bucket tương ứng; paging không bỏ sót hàng. Cache cursor được ghi atomically với các hàng liên quan.
- Offline sau nâng cấp v3/v4 vẫn đọc được dữ liệu đo cũ đúng trạm. Đổi múi giờ điện thoại không xóa cache đo; tổng hợp ngày có ranh giới cũ không được trình bày như dữ liệu ngày mới. Lỗi API một resource không xóa resource khác.
- Catalogue có vị trí khi online và fallback offline. Chuyển trạm A → B khi response A về muộn không hiển thị dữ liệu A dưới tên B.
- Kiểm tra query plan, độ trễ và số hàng trả về cho khoảng 7 ngày; build/test backend, Flutter test và analyzer đạt trước khi chốt P05.

## Ngoài phạm vi

Không suy ra múi giờ từ tọa độ trạm, không tự nhận diện vị trí điện thoại, không thay đổi giao thức firmware chỉ để gắn vị trí, không coi rate legacy là amount quan sát được và không ép dùng Timescale.

**Tham chiếu:** P03 station catalogue, P04 minute-log v2, P00 telemetry contract; `BE-PLAN-03`, `APP-PLAN-02–04`, `CROSS-02`.
