# Review Device API: các điểm lệch và nguy cơ

Ngày ghi nhận: 24/11/2026 (UTC+7).

Chi tiết kiểm tra schema, bổ sung unique/check và RLS: [hướng dẫn SQL Supabase](SUPABASE_DEVICES_SQL.md).

## 1. Phạm vi và bằng chứng

- Nhánh review: `feature/device-api`, commit `2ca98e6`.
- Nhánh đối chiếu: `master`, commit `41571a4`.
- `master` là ancestor của nhánh feature, chênh lệch 3 commit, 19 file. Có thể fast-forward về mặt Git; điều này không bảo đảm chức năng đã sẵn sàng cho production.
- Tài liệu được tạo khi workspace đang ở `feat/firmware-refinement-phase1`. Các kết luận code dưới đây đối chiếu bằng `git show feature/device-api:...`, không suy từ firmware của nhánh đang checkout.
- Schema Supabase đã được đọc qua REST trong phiên kiểm tra ngày 24/11/2026. Bảng `public.devices` có 5 thiết bị, từ `adht_weather_01` đến `adht_weather_05`. Tại thời điểm đọc, các MAC không trùng và đúng định dạng chữ hoa.
- Metadata REST xác nhận `device_id` là primary key; chưa đủ thông tin để kết luận MAC đã có unique index/constraint hay trạng thái RLS/policy. [hướng dẫn SQL Supabase](SUPABASE_DEVICES_SQL.md) giúp kiểm tra trực tiếp.
- Không xác định được ngày tạo bảng từ bằng chứng hiện có. Ngày commit API 17/11/2026 không phải bằng chứng về ngày tạo bảng.
- SQL trong tài liệu chưa được chạy trên Supabase. Không có thay đổi database trong quá trình lập tài liệu này.

## 2. Schema và API hiện tại

| Thành phần | Hiện trạng | Hệ quả |
| --- | --- | --- |
| `public.devices` | Có `device_id`, `name`, `mac` và 7 cột cấu hình | Bảng đã tồn tại; không cần tạo lại để sử dụng API danh mục |
| `POST /api/devices` | DTO nhận `device_id`, `name`, `mac`; trả ba trường này | Các cột cấu hình được database điền default khi insert |
| `GET /api/devices`, `GET /api/devices/:id` | Chỉ select `device_id,name,mac` | App chưa đọc được cấu hình đã lưu trong DB qua các API này |
| `PUT /api/devices/:id/config` | Nhận cấu hình rồi publish MQTT | Chưa ghi cấu hình vào DB; chưa xác nhận ESP32 đã áp dụng |
| ESP32 | Lưu cấu hình nhận được vào NVS | Có thể khác cấu hình trong DB và form app |
| Flutter | Form dùng default trong code; danh sách trạm hard-code | Chưa đồng bộ danh mục và cấu hình từ database |

Các cột cấu hình live đều NOT NULL, có default: `temp_max=38`, `temp_min=10`, `humi_max=90`, `wind_max=15`, `rain_max=50`, `auto_warning=true`, `buzzer=true`. Default không đồng nghĩa giá trị của mọi dòng đều giống nhau.

Schema live không expose `created_at`. Các API hiện tại không đọc trường này. Không suy ngày tạo bảng từ tên file migration hoặc từ ngày tạo dữ liệu.

## 3. Các vấn đề và nguy cơ

Mức **cao**: cần xử lý trước khi mở cho người dùng không tin cậy hoặc khi cam kết cấu hình đã đồng bộ. Mức **vừa**: cần xử lý để bảo đảm hành vi nhất quán. Phân biệt thay đổi mới của feature với hạn chế đã có trên master.

### D01 — DB và cấu hình thực tế trên thiết bị chưa đồng bộ (cao, có từ master)

Bằng chứng: `adht-weather-backend/src/modules/devices/devices.service.ts`, hàm `updateConfig()` chỉ gọi `mqttService.publishConfig()`; không update `devices`.

Ví dụ: gửi `temp_max=40` có thể cập nhật ESP32, trong khi DB vẫn lưu 38. Sau đó đọc DB không phản ánh đúng cấu hình đang chạy. Ngược lại, sửa DB trực tiếp cũng không tự gửi cấu hình xuống ESP32.

Hướng xử lý: phân biệt cấu hình mong muốn và cấu hình thiết bị đã xác nhận; lưu trạng thái đồng bộ, phiên bản cấu hình và thời điểm ACK. Chỉ ghi DB trước hoặc sau publish đều chưa giải quyết được lỗi một trong hai bước thất bại; cần trạng thái pending/failed và cơ chế retry.

### D02 — Broker ACK bị hiểu thành thiết bị đã lưu cấu hình (cao, có từ master)

Bằng chứng: `adht-weather-backend/src/modules/mqtt/mqtt.service.ts` publish QoS 1, `retain: false`; callback thành công xác nhận broker nhận bản tin. Backend trả `status: success`, Flutter hiển thị “Đã lưu cấu hình tới trạm”.

Nguy cơ: ESP32 offline hoặc xử lý lỗi nhưng app vẫn báo đã lưu. `retain: false` không cung cấp cơ chế phát lại cấu hình cuối cho lần subscribe mới; việc giao lại còn tùy session MQTT. QoS 1 cũng cho phép giao trùng.

Hướng xử lý: trả trạng thái “đã gửi/chờ xác nhận”; thêm request ID, config version, ACK từ thiết bị sau khi áp dụng/lưu NVS, timeout và xử lý trùng. Không bật retain cho command như reset/còi như một cách sửa chung.

### D03 — Backend cho phép cập nhật một phần, firmware thay các trường thiếu bằng default (cao, có từ master)

Bằng chứng: `UpdateConfigDto` đánh dấu cả bảy trường `@IsOptional()`. Firmware của `feature/device-api`, file `adht-weather-firmware/src/network/mqtt_manager.cpp`, tạo `SystemConfig` mới và gán default cho các trường thiếu; `handleMqttConfig()` ghi toàn bộ cấu hình đó vào NVS.

Ví dụ: gửi `{"buzzer":false}` có thể làm `temp_max` từ 40 về 38 và `rain_max` về 50. Gửi body `{}` cũng có thể reset cấu hình về default. Đây là hành vi của firmware trên nhánh review; không áp kết luận này cho firmware nhánh refinement nếu đã sửa cách xử lý patch.

Hướng xử lý: thống nhất contract patch (giữ nguyên trường không gửi) hoặc bắt buộc gửi cấu hình đầy đủ; bổ sung test xuyên backend/firmware và từ chối body rỗng. Phải kiểm tra cả trường hợp `null`, vì `@IsOptional()` bỏ qua validation cho `null`.

### D04 — API GET chưa trả cấu hình, form không tải cấu hình theo thiết bị (vừa)

Phần mới của feature: `SupabaseService.getDevice()/getDevices()` chỉ select ba cột định danh; `Device` type cũng chỉ có ba trường. Phần app đã có từ master: `DeviceConfigModel.initialDefault()` khởi tạo form, chưa có luồng GET cấu hình để nạp khi chọn trạm.

Nguy cơ: app hiển thị default thay cho cấu hình đang lưu; khi đổi trạm, form có thể giữ giá trị của trạm trước rồi gửi sang trạm mới. Không được coi response echo body của PUT là cấu hình đã đọc lại từ thiết bị.

Hướng xử lý: thêm endpoint đọc cấu hình hoặc mở rộng response GET; reload state theo device ID; hiển thị rõ cấu hình mong muốn và cấu hình đã xác nhận.

### D05 — Giá trị mặc định và nguồn ngưỡng cảnh báo khác nhau (vừa, có từ master)

- DB live: default `rain_max=50`.
- Firmware nhánh review: NVS chưa có giá trị thì dùng 50.
- Flutter: form mặc định dùng 30.
- Backend: default `ALERT_RAIN_MAX` là 30; cấu hình môi trường có thể ghi đè.
- `NotificationsService.checkAndAlert()` dùng ngưỡng cấu hình backend, chưa đọc ngưỡng riêng của từng dòng `devices` và chưa sử dụng `auto_warning` trong DB.

Nguy cơ: còi tại ESP32 và push notification cảnh báo ở ngưỡng khác nhau. Firmware nhánh review cũng chỉ kiểm tra nhiệt độ cao, gió và mưa trong `taskAlert`, dù nhận cả `temp_min` và `humi_max`; lưu được một trường không đồng nghĩa mọi chức năng đã dùng nó.

Hướng xử lý: thống nhất default, đơn vị và ý nghĩa từng trường; xác định `auto_warning` điều khiển còi cục bộ hay cả FCM. Chưa tự sửa default/giá trị cấu hình của người dùng bằng bộ SQL đi kèm.

### D06 — Chưa có xác thực/phân quyền cho API thiết bị (cao)

Feature bổ sung endpoint public tạo thiết bị và đọc danh mục/MAC. Các endpoint command/config đã có trên master cũng chưa có guard xác thực. Backend dùng service-role key truy cập Supabase.

Nguy cơ: người ngoài tạo thiết bị giả, chiếm device ID/MAC trước thiết bị hợp lệ, đọc danh mục hoặc gửi lệnh/config nếu truy cập được endpoint. MAC unique chỉ bảo đảm không trùng, không chứng minh quyền sở hữu phần cứng.

Hướng xử lý: xác thực ở backend, phân quyền quản lý/điều khiển từng thiết bị. RLS không ngăn request đi qua một backend không xác thực sử dụng service-role; CORS cũng không phải cơ chế xác thực.

### D07 — Contract 409 cho MAC phụ thuộc unique thực tế trong DB (vừa, liên quan feature mới)

`createDevice()` chỉ đổi lỗi PostgreSQL `23505` thành HTTP 409. Chưa xác nhận DB có unique cho MAC; không có bản ghi trùng tại thời điểm kiểm tra không chứng minh constraint tồn tại.

Nếu thiếu unique, hai request đồng thời có thể tạo hai thiết bị cùng MAC. Việc trim/uppercase trong DTO chỉ áp dụng cho đường API; ghi trực tiếp DB có thể bỏ qua. Các lệnh trong [hướng dẫn SQL Supabase](SUPABASE_DEVICES_SQL.md) thêm NOT NULL, check format MAC chữ hoa và unique, không tự đổi hoặc xóa dữ liệu cũ.

### D08 — Validation định danh/cấu hình chưa nhất quán (vừa)

Feature cho phép `device_id` là chuỗi không rỗng bất kỳ, nhưng MQTT publisher từ chối ID chứa `/`, `+`, `#` hoặc NUL. Có thể đăng ký thành công một ID rồi không điều khiển được qua publisher. GET và PUT/command cũng chưa kiểm tra cùng một contract định danh hay sự tồn tại trong registry.

`UpdateConfigDto` kiểm tra kiểu số/boolean, chưa kiểm tra `temp_min <= temp_max`, độ ẩm 0–100 hoặc gió/mưa không âm. Nguy cơ lưu/gửi cấu hình vô nghĩa.

Hướng xử lý: thống nhất validation ID từ đăng ký tới MQTT; kiểm tra cấu hình theo domain ở backend và firmware. Không thêm ràng buộc ID mới vào DB trong bộ SQL đi kèm khi chưa thống nhất quy tắc tương thích dữ liệu cũ.

### D09 — Flutter chưa lấy danh mục thiết bị từ API mới (vừa, phần tích hợp còn thiếu)

Bằng chứng: `adht-weather-app/lib/core/constants/api_constants.dart` hard-code 3 trạm; `DeviceApiService` chỉ có command/config. DB live đã có 5 trạm.

Nguy cơ: thiết bị mới tạo không xuất hiện trong app; tên hiển thị lệch DB. Đăng ký DB cũng chưa provision firmware, MQTT identity hoặc ACL broker.

Hướng xử lý: lấy danh sách/tên từ GET devices, cache danh mục khi offline; có quy trình provision và xác minh thiết bị riêng.

### D10 — GET danh sách có thể thiếu dữ liệu khi Supabase giới hạn trang dưới 500 (vừa, feature mới)

Bằng chứng: `SupabaseService.getDevices()` dùng page size 500, tăng offset cố định 500 và dừng khi `data.length < 500`. Nếu giới hạn server là 100, API trả 100 dòng rồi dừng dù còn dữ liệu.

Hướng xử lý: đọc đến trang rỗng và tăng offset theo số dòng thực nhận, hoặc pagination/cursor có contract rõ ràng. API đang trả toàn bộ danh sách cũng cần giới hạn quy mô/chi phí; hiện 5 dòng chưa gặp lỗi này.

### D11 — Linux runner chưa có SQLite runtime phù hợp (vừa, feature mới)

Commit `5af5661` thêm Linux runner; `main.dart` chưa khởi tạo SQLite FFI cho Linux, `AppDatabase` vẫn dùng factory mặc định, `sqflite_common_ffi` chỉ ở dev dependencies.

Nguy cơ: app Linux lỗi khi truy cập SQLite, ảnh hưởng dashboard/history/cache. Hướng xử lý: đưa implementation desktop vào runtime dependency, khởi tạo factory theo platform và smoke-test Linux; có thể tách Linux runner khỏi PR Device API.

### D12 — Thiếu lịch sử schema được quản lý và kiểm thử tích hợp thực tế (vừa)

Code feature tương thích các cột live đã kiểm tra nhưng repository chưa có baseline đầy đủ tái tạo bảng `devices` cùng 7 cột cấu hình/default. Bản migration tối giản từng được soạn trong phiên này không đại diện toàn bộ schema live và chưa được apply. File đó không còn trong workspace tại lúc lập tài liệu này.

Chỉ `CREATE TABLE IF NOT EXISTS` không bổ sung cột/constraint vào bảng đã tồn tại. RLS/policy và grants cũng cần kiểm tra trực tiếp. Bộ SQL trong [hướng dẫn SQL Supabase](SUPABASE_DEVICES_SQL.md) là thay đổi bổ sung cho bảng hiện hữu, không phải baseline cho project mới.

Hướng xử lý: sau khi xác minh catalog, xuất baseline đúng schema live; quản lý migrations tiếp theo trong Git. Test qua mock chưa chứng minh quyền DB, unique hoặc nhận/lưu cấu hình trên thiết bị thật.

## 4. Kiểm thử đã thực hiện trong phiên review trước

- Backend build và test file devices đã pass; diff không có lỗi whitespace.
- Toàn bộ backend chưa xanh: forecast test mock logger thiếu `log()`; test Socket.IO bị sandbox chặn listen. Đây không phải thay đổi mới của Device API.
- Flutter/Linux chưa kiểm chứng build/runtime vì Flutter qua snap không chạy được trong môi trường kiểm tra.
- Không kiểm thử ghi DB, gửi cấu hình hoặc điều khiển ESP32 live. Các nhận định về tác động runtime dựa trên code, cần xác nhận bằng test tích hợp sau khi sửa.

## 5. Thứ tự xử lý đề xuất

1. Kiểm tra catalog và chạy SQL bổ sung unique/check theo [hướng dẫn SQL Supabase](SUPABASE_DEVICES_SQL.md); lưu SQL đã chạy vào migration được quản lý trong Git.
2. Bảo vệ API đăng ký/điều khiển và thống nhất validation định danh, cấu hình.
3. Sửa contract cập nhật một phần, đồng nhất default và ý nghĩa từng ngưỡng.
4. Bổ sung đọc/lưu cấu hình, trạng thái đồng bộ và ACK từ ESP32; tích hợp danh mục/form theo thiết bị vào Flutter.
5. Sửa phân trang, hoàn thiện hoặc tách Linux runner; kiểm thử tích hợp với schema thực và thiết bị offline/reconnect trước khi kết luận merge production.
