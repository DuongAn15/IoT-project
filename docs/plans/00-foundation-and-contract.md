# P00 — Baseline và contract

**Trạng thái:** P00 đóng với ngoại lệ staging được ghi rõ theo yêu cầu close-out của người dùng. Baseline, catalog/ACL và board runtime đã được ghi; project Supabase live/non-staging (ref `umsysvgxprlwpqmblwie`, SQL Editor role `superuser`). P01 hardening và anon REST denial (GET 401/42501) đã xác minh; telemetry/app hoạt động. Broker live read-only subscribe nhận 4 message sau khi khôi phục production. Probe MQTT live bằng credential backend `.env` và client ID tạm được SUBACK QoS 0 trên topic command tổng hợp ngẫu nhiên. Người dùng xác nhận quyền/topic hiện tại là đúng theo cấu hình và không yêu cầu remediation ACL; không publish. Không có broker staging; ghi nhận ngoại lệ này, không chạy thêm live ACL tests theo chỉ đạo. Contract v2 semantics và fixtures đã chốt ở mức thiết kế; JSON Schema/validator và implementation thuộc PR-01.
**Mục tiêu:** tạo baseline đủ tin cậy để các plan tiếp theo làm song song mà không phát triển lệch contract.

## Phạm vi

- Ghi commit/source baseline, toolchain và lệnh build/test cho backend, Flutter, firmware.
- Lưu fixtures versioned cho payload v1 hiện tại và contract v2; định nghĩa identity, timestamp, quality, rain rate/amount, ACK và error semantics.
- Audit read-only schema, grants, RLS, index và giới hạn phân trang Supabase; không thay dữ liệu production.
- Chốt broker/DB/board staging, test credentials riêng, quota và người có quyền truy cập.
- Ghi nhận số đo board hiện có: build, heap/stack nếu đo được, wiring UP/DOWN; giữ secrets ngoài fixtures/log.

## Ngoài phạm vi

Không chạy migration live, không bật publisher v2, không đổi topic production, không commit credential.

## Baseline đã chạy

- **Baseline source:** commit `0d28f45df4f213117d5910c797955789ae0fa273` (`docs: split IoT roadmap into focused execution plans`).
- **Nhánh thực hiện:** `docs/p00-baseline-contract`.
- Các kết quả dưới đây là baseline tại source commit trên; không bao gồm thay đổi contract fixture của P00.

| Thành phần | Toolchain | Lệnh | Kết quả |
| --- | --- | --- | --- |
| Backend (`adht-weather-backend`) | Node `v26.13.1`, npm `11.20.0`, Bun `1.4.2` | `bun run build` | Pass |
| Backend tests tại baseline source | Node `v26.13.1` | `node --test test/*.test.cjs` | **32/36 pass** trước khi tạm ngưng forecast. Bốn test fail kiểm tra route/service forecast còn stub; logger mock cũng thiếu `log()`. Forecast được hoãn, không phải triển khai để sửa baseline. Trên branch này route/service/config đã comment out và cả 8 test forecast được skip; lần chạy lại đạt **28 pass, 0 fail, 8 skipped**. |
| Flutter app (`adht-weather-app`) | Flutter `3.47.9`, Dart `3.13.7` | `flutter analyze`; `flutter test` | Analyze pass; **23 tests pass** |
| Firmware (`adht-weather-firmware`) | PlatformIO `6.2.0` | `pio run` | Pass cho ESP32-D0WD-V3. RAM: `50,584 / 327,680` bytes; flash: `1,197,052 / 3,145,728` bytes. Đây là kết quả build, không phải phép đo heap/stack khi chạy trên board. |
| Simulator tests (`tools/test_simulate_nodes.py`) | Python `3.12.3` | `python3 tools/test_simulate_nodes.py` | **5/5 pass** khi `/tmp/opencode` tồn tại; test tạo thư mục tạm bên dưới đường dẫn cố định này. Không sửa test hoặc mã sản phẩm trong P00. |
| Contract fixtures | Python `3.12.3` | Parse toàn bộ `docs/contracts/**/*.json` bằng `json.loads` | **9/9 JSON parse thành công**. Đây chỉ là kiểm tra cú pháp JSON, không phải xác nhận schema v2 đã được chốt. |

## Toolchain ghi nhận

| Công cụ | Phiên bản |
| --- | --- |
| Node.js | `v26.13.1` |
| npm | `11.20.0` |
| Bun | `1.4.2` |
| Python | `3.12.3` |
| Flutter | `3.47.9` |
| Dart | `3.13.7` |
| PlatformIO Core | `6.2.0` |

## Contract và fixture

Các fixture ở [`../contracts/README.md`](../contracts/README.md) phân biệt **v1 quan sát từ source hiện tại** với **v2 design contract đã chốt cho P00**. Chúng không chứng minh v2 đã được triển khai; JSON Schema/validator được deferred tới PR-01.

- v1: telemetry hợp lệ và telemetry humidity ngoài miền.
- v2: minute log hợp lệ; invalid missing sequence; invalid counter decrease; config desired/applied; command request/completed/failed; history response.
- Minute-log mẫu có rain counter không đổi, `calibration_version`, và không có v1 event-rate. Backend suy ra `rainfall_mm`; history fixture dùng lượng mưa dạng amount.
- Identity, observed/received time, units, per-sensor quality, rain rate/amount, command status, retry, duplicate/conflict và giới hạn ý nghĩa PUBACK được mô tả trong contract README.
- **v2 design semantics đã chốt cho P00:** raw rain counts/epoch/versioned backend calibration; interval boundary, partial/unknown coverage, metric quality, wind window semantics, config lifecycle, command states/error codes được ghi tại contract README. Chưa có JSON Schema/validator; PR-01 phải thêm chúng và automated expected-outcome tests trước P04/publisher. V2 chưa được triển khai.

## Rà soát Supabase từ source và catalog audit

- `SupabaseService` dùng `devices` với các cột backend đọc là `device_id`, `name`, `mac`; bảng telemetry lấy từ `SUPABASE_TABLE` (mặc định `weather_logs`). Insert telemetry ánh xạ `temp` → `temperature`, `humi` → `humidity`, cùng `rain_rate`, `wind_speed`, `device_id`, `created_at`.
- `getLatest()` lọc `device_id` nếu có, sắp `created_at DESC, id DESC`, lấy một dòng. `getHistory()` lọc theo device/time range, sắp `created_at ASC, id ASC`, page 500 dòng và lặp tới trang rỗng. Các index thực tế chưa xác minh.
- `getDevices()` yêu cầu page 500, tăng offset cố định 500 và dừng khi nhận ít hơn 500. Nếu PostgREST cap thấp hơn 500 thì có thể trả thiếu trang; đây là vấn đề từ code, không phải kết quả đã tái hiện trên staging.
- Backend chọn key theo thứ tự `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_KEY`, `SUPABASE_ANON_KEY`; người dùng xác nhận `SUPABASE_SERVICE_ROLE_KEY` được thiết lập trong backend đang chạy, nên config hiện chọn key này trước. Hai REST probe chỉ dùng `SUPABASE_ANON_KEY` lấy nội bộ từ `.env`; không in/lưu giá trị.
- Bộ query [`p00-supabase-readonly-audit.sql`](../p00-supabase-readonly-audit.sql) (chỉ SELECT) đã được người dùng chạy trong SQL Editor; kết quả được lưu tại [`p00-staging-audit-template.md`](../p00-staging-audit-template.md). Người dùng xác nhận project đang lưu dữ liệu thật nên được phân loại live/non-staging; dữ liệu có thể bỏ. Project ref `umsysvgxprlwpqmblwie`, SQL Editor role `superuser`.
- Catalog cho thấy `devices` có PK `device_id`, unique MAC và checks đã validated; `weather_logs` có PK `id`, FK `device_id`, cột measurement khớp mapping backend. `weather_logs.device_id` nullable/default `'adht_weather_01'`. Follow-up xác nhận `id` là `GENERATED BY DEFAULT AS IDENTITY`, sequence `public.weather_logs_id_seq`; backend không gửi `id` thì DB tự sinh.
- Tại thời điểm audit, cả hai bảng bật RLS nhưng `force_rls=false`; `weather_logs` có policy public SELECT/INSERT và grants rộng cho `anon`/`authenticated`; Follow-up B xác nhận column grants trên mọi cột. Đây là finding P1. Người dùng báo đã chạy P01 hardening; hậu kiểm catalog xác nhận RLS còn bật, policy query rỗng, chỉ `service_role` còn grants trong kết quả đã kiểm tra. Người dùng xác nhận telemetry write và app read bình thường sau thay đổi. GET sau hardening tới `/rest/v1/weather_logs?select=id&limit=1`, dùng anon key, trả HTTP `401`, mã PostgreSQL `42501` (`permission denied for table weather_logs`); không in/lưu key hoặc row ID. Quyền `TRUNCATE` trước hardening không bị RLS giới hạn.
- Index hiện có trên `devices(device_id)`/MAC và các index riêng `weather_logs(created_at)`, `weather_logs(device_id)`, PK `id`; chưa có composite index theo filter/order backend. `weather_logs` có khoảng 37,593 live rows theo thống kê ước lượng, không phải exact count.
- Follow-up column-grants đã hoàn tất; người dùng xác nhận PostgREST Max Rows = 1000, lớn hơn page size 500 của `getDevices()` và `getHistory()`. Project ref và SQL Editor role đã ghi. Chưa xác minh hoặc provision broker staging riêng với project live. Hai REST HEAD probes anon trước đó trả HTTP 200 nhưng không thay thế catalog review.
- Môi trường agent không có `psql`/Supabase CLI/direct PostgreSQL connection. Người dùng chạy catalog SQL và P01 hardening, sau đó cung cấp kết quả hậu kiểm; agent không dùng service-role key và không thực hiện DDL/DML.

## Board và môi trường tích hợp

- Người dùng xác nhận bằng phép thử trước đó: GPIO35/34 (UP/DOWN) ở mức `1` khi không bấm và `0` khi bấm (active-low).
- Firmware production trong project đã được khôi phục sau diagnostic build; build PlatformIO pass như bảng trên.
- **Serial observation (2026-11-26):** nghe `/dev/ttyUSB0` ở `115200`, DTR/RTS inactive, tối đa 10 giây. Log lặp `[WiFi] Still connecting...`, sau đó có banner `POWERON_RESET` và firmware bắt đầu kết nối WiFi lại. Không thấy log MQTT connect trong phiên serial; chưa rõ reset có liên quan việc mở serial hay không, nên monitor có thể đã làm board reset. Phiên này không gửi payload/lệnh. Sau đó người dùng xác nhận app vẫn nhận telemetry bình thường.
- **Runtime heap/stack diagnostic (2026-11-26):** firmware chẩn đoán tạm lấy 3 mẫu cách nhau 30 giây. Heap tự do hiện tại `149,008–149,052 B`; mức thấp nhất từ boot `129,172 B` (mẫu đầu `138,916 B`). High-water mark là stack còn trống thấp nhất quan sát được; kích thước task theo source:

  | Task | Stack cấp phát | Stack còn trống thấp nhất | Ước lượng đã dùng cao nhất |
  | --- | ---: | ---: | ---: |
  | `SensorsTask` | 4,096 B | 2,880 B | 1,216 B |
  | `NetworkTask` | 10,240 B | 6,332 B | 3,908 B |
  | `DisplayTask` | 4,096 B | 1,800 B | 2,296 B |
  | `AlertTask` | 4,096 B | 2,776 B | 1,320 B |

  Đây là phép đo khoảng 90 giây sau boot, không phải soak test; logger chạy trong `NetworkTask` nên có thêm một ít stack overhead. Source chẩn đoán đã được gỡ; production build pass và đã nạp lại. Sau khi khôi phục, broker read-only observer nhận 4 telemetry message trong 20 giây, không in payload.
- **Broker live read-only observation (2026-11-26):** dùng TLS/config và credentials MQTT từ backend `.env` mà không in giá trị; client ID tạm riêng subscribe đúng topic `adht/weather/adht_weather_01/telemetry` trong 15 giây. Broker cấp subscription; nhận 2 message, payload không được ghi/in. Sau đó một probe riêng SUBSCRIBE QoS 0 tới topic tổng hợp ngẫu nhiên `adht/weather/acl_probe_6f5d3eb5d4c7a7f8/command` và nhận SUBACK grant QoS 0; ngắt ngay, không publish và không xử lý/in payload. Người dùng xác nhận quyền/topic hiện tại là đúng theo cấu hình và không yêu cầu remediation ACL. Kết quả chỉ xác nhận SUBSCRIBE được cấp cho credential + client ID tạm này; không chứng minh quyền publish hay ACL của client ID production.
- Catalog results và follow-up identity/column-grants đã được ghi; project live/non-staging, ref `umsysvgxprlwpqmblwie`, SQL Editor role `superuser`. P01 hardening đã được người dùng áp dụng và hậu kiểm catalog xác nhận ACL. PostgREST Max Rows = 1000. Người dùng xác nhận chưa có broker staging riêng. Agent không dùng service-role key, không chạy DDL/DML; trên broker chỉ subscribe read-only vào telemetry và topic probe tổng hợp, không publish.

## Trạng thái nghiệm thu

| Tiêu chí | Trạng thái | Ghi chú / việc còn lại |
| --- | --- | --- |
| Build/test baseline có kết quả thực | Đạt có ghi chú | Baseline gốc được lưu; sau khi tạm comment forecast, backend build pass và test đạt 28 pass, 8 skipped. Các test forecast được giữ lại để tham khảo khi mở lại feature. |
| Contract có fixture hợp lệ/không hợp lệ và field owner | Đạt có ghi chú | v1/v2 có valid/invalid fixtures; v2 design semantics và field owners đã ghi. JSON Schema/validator và implementation là gate PR-01 trước khi bật publisher. |
| Supabase schema/ACL được ghi nhận read-only | Đạt | User cung cấp catalog + follow-up A/B và post-check: schema/constraints/indexes/identity đã ghi; hậu kiểm xác nhận policy rỗng, không còn anon/authenticated grants trong các kết quả, `service_role` còn. GET bằng anon key trả HTTP 401/42501; telemetry write và app read hoạt động; Max Rows = 1000 > page size 500. |
| Staging tách identity/credential khỏi project live | Ngoại lệ P00; chưa đạt | Chưa có staging broker. Live ACL probe nhận SUBACK grant QoS 0 trên topic `command` tổng hợp; người dùng xác nhận quyền/topic hiện tại là đúng và không yêu cầu follow-up ACL. Không có publish test; probe không đại diện client ID production. Ngoại lệ còn lại là không có staging riêng, không phải việc ACL đang chờ xử lý theo xác nhận hiện tại. |
| Board build và UP/DOWN wiring được ghi nhận | Đạt có ghi chú | Build pass; mức logic UP/DOWN do người dùng xác nhận; heap/stack runtime đã đo bằng firmware tạm (3 mẫu/90 giây), sau đó khôi phục và nạp production thành công. Đây chưa phải soak test. |

## Phụ thuộc và thứ tự

P00 được đóng với ngoại lệ staging nêu trên. Người dùng xác nhận ACL/topic hiện tại là đúng và không yêu cầu thêm test hoặc thay đổi ACL; live probe chỉ ghi nhận SUBSCRIBE được cấp cho client ID tạm, không kiểm tra quyền publish. Nếu sau này cần chạy ACL/publish tests tách biệt hoặc rollout v2, provision broker staging có identity/ACL/quota riêng trước.

## Rollback

Docs/fixtures/tooling additive; revert PR mà không ảnh hưởng DB hay thiết bị.

**Tham chiếu:** [`SYSTEM_REVIEW_AND_ARCHITECTURE.md`](../SYSTEM_REVIEW_AND_ARCHITECTURE.md), mục 1, 7, 14, 16–18.
