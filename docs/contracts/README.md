# Contract fixtures — P00

Cập nhật: 26/11/2026. Đây là fixtures cho baseline và contract mục tiêu, không phải bằng chứng rằng backend/firmware đã triển khai v2.

## Trạng thái

- `v1/`: payload đang quan sát trong firmware/backend hiện tại; giữ để test adapter tương thích.
- `v2/`: contract semantics được chốt cho P00 ngày 26/11/2026; các fixture là ví dụ, không phải bằng chứng firmware/backend đã triển khai. JSON Schema/validator và implementation vẫn là gate PR-01 trước khi P04 bật publisher.
- Hướng mưa do owner xác nhận: raw tip counts + epoch đổi khi reboot/reset; backend dùng calibration có version để suy ra amount. Các default chi tiết được ghi ở mục `V2 defaults selected for P00`.
- JSON fixtures chứa dữ liệu giả, không chứa credentials hoặc dữ liệu từ Supabase/board thật.

## Route và semantics hiện tại/đích

| Version/type | Topic / route | Producer → consumer | ACK/ý nghĩa |
| --- | --- | --- | --- |
| v1 telemetry | `adht/weather/{device_id}/telemetry` | ESP32 → backend | PubSubClient publish hiện là QoS 0; không có business ACK/DB ACK |
| v1 status | `adht/weather/status` | ESP32/LWT → backend | Topic chung, retained; payload dùng `device`, không thay cho registry/auth |
| v1 command | `adht/weather/{device_id}/command` | Backend → ESP32 | Backend success hiện chỉ có thể xác nhận broker publish ACK, không chứng minh thiết bị thực thi |
| v1 config | `adht/weather/{device_id}/config` | Backend → ESP32 | Payload patch; firmware hiện merge vào cấu hình đang chạy |
| v2 minute log | `adht/weather/{device_id}/telemetry/log` | FW → BE | QoS 1 là mục tiêu; PUBACK không đồng nghĩa DB commit |
| v2 command | `.../command/request/{request_id}` và `.../command/response/{request_id}` | BE ↔ FW | `accepted` không phải `completed`; response phải khớp request/deployment/boot |

## Bằng chứng từ firmware v1 hiện tại

- `rain_total` là lượng mưa của phiên chạy: firmware cộng `rainPulses × mmPerPulse` vào RAM. `WeatherData` khởi tạo giá trị 0; lệnh `reset_rain` cũng đưa total về 0. Giá trị này không được lưu trong NVS và firmware v1 không publish raw tip counter hay epoch, nên không phải lifetime cumulative counter ổn định qua reboot/reset.
- `rain_rate` hiện được tính bằng cửa sổ trượt 180 giây (`RAIN_TIMEOUT_SEC`, cộng dồn số xung trong 3 phút gần nhất × `mmPerPulse × 3600 / 180`), tự trượt về 0 sau 180 giây không có pulse (chống rung `RAIN_DEBOUNCE_MS = 400 ms` kèm kiểm tra mức `LOW` trong ISR). `RAIN_SAMPLE_PERIOD_SEC = 60` chỉ được dùng cho chu kỳ đóng `minute_log` v2. Vì vậy không diễn giải v1 `rain_rate` thành lượng mưa trong một phút.
- `wind_speed` được tính từ pulse count trong mỗi khoảng khoảng 5 giây. `wind_max` là peak của ring buffer 120 mẫu 5 giây (10 phút), cả hai chỉ ở RAM và cửa sổ max bắt đầu lại sau reboot. Đây không phải chuẩn gust 3-second mean.
- **Hướng v2 đã được owner đồng ý (26/11/2026):** dùng raw tip counts, epoch mới khi reboot hoặc reset thủ công, backend suy ra `rainfall_mm` bằng calibration có version. Nếu API cần rate, backend suy ra rate trung bình từ amount/interval; minute log không nhận v1 event-rate. Firmware v1 hiện chưa phát raw count/epoch; `rain_total` v1 không thể thay thế counter này. Fixture v2 mang `calibration_version`; các default chi tiết được chốt bên dưới.

## Field owner và semantics

| Field/nhóm | Owner tạo | Quy tắc contract |
| --- | --- | --- |
| `device_id` | Firmware provision; backend registry kiểm tra | ID trong topic phải khớp payload; ID/MAC tự khai không phải credential/authentication |
| `deployment_id`, station binding | Backend registry | Backend xác định station theo deployment tại thời điểm quan trắc; không suy từ mapping hiện tại khi đọc log cũ |
| `boot_id`, `window_sequence`, `event_id`, `request_id` | Firmware tạo boot/window/event; backend tạo request | `boot_id` mới mỗi boot; `window_sequence` tăng cho mỗi log mới trong boot. Log identity là `(device_id,deployment_id,boot_id,window_sequence)`; retry giữ nguyên identity và payload. Cùng identity + payload khác là conflict |
| v1 `timestamp` | Firmware nếu có | DTO hiện nhận Unix seconds optional nhưng firmware hiện không gửi; backend đang dùng receive time khi thiếu. Receive time không được gọi là observed time |
| v2 `interval_start/end`, `occurred_at` | Firmware | ISO-8601 UTC; interval half-open `[start,end)`, mục tiêu 60s; cho phép interval ngắn để đóng tại reset/deployment/calibration boundary. Clock unsynchronized dùng uptime bounds, không bịa UTC |
| `received_at` | Backend | Thời điểm backend nhận; không ghi đè observed time của backlog |
| temperature | Firmware | `degC`; giữ sum/count/min/max/latest để aggregate đúng; thiếu/invalid không biến thành 0 |
| humidity | Firmware | `%RH`; quality/count riêng sensor |
| rain rate | v1 firmware; v2 backend nếu cần | v1 `rain_rate` là rolling-window rate trên cửa sổ 180 giây; không có trong v2 minute-log input. Nếu API cần rate, backend tính `rain_rate_avg_mm_h = rainfall_mm × 3600 / interval_seconds`; không cộng các rate để thành tổng mm |
| rain counter/amount | Firmware sở hữu raw tip counts/epoch; backend sở hữu calibration lookup và dẫn xuất amount | `counter_epoch` mới mỗi boot/reset; `tip_count_start/end` tăng đơn điệu trong epoch. `rainfall_mm = delta tips × mm_per_tip[calibration_version]` chỉ khi epoch/calibration/coverage hợp lệ. Thiếu baseline hoặc qua ranh giới thì partial/unknown, không nối epoch âm thầm. `rainfall_mm` không nằm trong minute-log input |
| wind | Firmware | `m/s`; trong minute log, max là peak của các mẫu 5s bên trong interval, không phải gust chuẩn 3s. Nếu cần rolling 10-min peak, field phải ghi rõ cửa sổ |
| `quality` | Firmware đo; backend bảo toàn/diễn giải | Mỗi metric có valid count; DHT/wind có expected count; coverage riêng rain. Missing khác zero; `observed`/`partial`/`unknown` không suy ra chỉ từ giá trị đo |
| `config_version` | Backend | Full desired snapshot; version tăng theo device/deployment. Duplicate cùng version/cùng content là idempotent; cùng version khác content là conflict; stale version bị từ chối. `applied` chỉ sau persist NVS và áp dụng runtime |
| command `status` | Firmware response | `accepted` = đã validate/đưa vào xử lý; `completed` = tác dụng hoàn tất; `failed` có code ổn định. Timeout = `unknown`; request ID giữ nguyên khi retry |

## V2 defaults selected for P00

- **Identity/time:** `boot_id` là ID duy nhất mỗi lần boot; `window_sequence` bắt đầu từ 1 và tăng mỗi log mới trong boot. Log identity là `(device_id, deployment_id, boot_id, window_sequence)`. Retry gửi lại cùng payload/identity. Interval là `[start,end)`, mục tiêu 60 giây; khi clock chưa sync, gửi `uptime_start_ms`/`uptime_end_ms` và `clock_quality=unsynchronized`, không gán observed UTC từ `received_at`.
- **Rain epoch/reset:** `counter_epoch` là opaque ID mới mỗi boot và mỗi `reset_rain`; `tip_count_start/end` là số nguyên không âm, tăng đơn điệu trong epoch. Manual reset đóng log partial cũ trước khi reset nếu có thể. Reboot đột ngột có thể làm mất phần cuối chưa gửi; biểu diễn gap là `partial/unknown`, không tính delta xuyên epoch. Calibration change cũng đóng/chia interval; backend giữ version-to-`mm_per_tip` catalog bất biến.
- **Rain amount/rate:** minute-log chỉ mang counts, epoch và `calibration_version`; backend tạo `rainfall_mm` khi counter/epoch/calibration/coverage hợp lệ. Delta 0 chỉ có nghĩa lượng mưa 0 khi coverage đầy đủ. Nếu cần rate ở API, dùng average `rain_rate_avg_mm_h = rainfall_mm × 3600 / interval_seconds`; không dùng v1 event-rate.
- **Metrics/quality:** `count` chỉ đếm sample hợp lệ; không có sample thì bỏ stats thay vì gán 0. Quality mang expected/valid counts theo sensor và coverage. Với cadence source hiện tại, một phút đầy đủ kỳ vọng 24 DHT samples và 12 wind samples; expected count phải tính theo cadence thực của version firmware. `coverage_ms` là thời gian collector hoạt động, không chứng minh sensor vật lý còn tốt. Rain zero cần full rain coverage và cùng epoch.
- **Wind/history:** v2 `wind_speed.max` là lớn nhất trong các mẫu 5s của interval, không gọi là gust chuẩn 3s. History dùng bucket UTC half-open, giữ quality/coverage; rainfall amount được cộng từ các interval hợp lệ. Late correction tăng `revision` và giữ `aggregation_version`.
- **Config:** backend là owner của full desired snapshot và version tăng theo device/deployment. Device report `accepted`, `applied` hoặc `failed`; `applied` yêu cầu cả persist NVS và apply runtime. Report gồm config version và snapshot đã áp dụng.
- **Commands/errors:** command request có `request_id`, `issued_at`, `expires_at`; expiry được kiểm tra trước execution. Same ID/same payload là idempotent; same ID/different payload là conflict. Response states là `accepted`, `completed`, `failed`; timeout không có response là `unknown`.

## Error và retry rules

1. Payload sai schema, ID/topic không khớp hoặc giá trị ngoài miền: reject/quarantine có lý do; không ghi thành telemetry hợp lệ.
2. Duplicate cùng business identity và cùng payload: idempotent, không nhân bản row/cảnh báo/command side effect.
3. Cùng business identity nhưng payload khác: conflict/audit, không overwrite âm thầm.
4. DB/network lỗi tạm thời: retry theo bounded policy và giữ nguyên identity; không ACK persisted trước DB commit.
5. Broker PUBACK chỉ chứng minh broker nhận message. HTTP `success`/MQTT PUBACK không chứng minh ESP32 đã lưu hoặc thực thi.
6. `error.code` dùng enum ổn định: `invalid_schema`, `identity_mismatch`, `invalid_counter_range`, `unknown_calibration`, `conflict`, `expired`, `unsupported_command`, `invalid_arguments`, `busy`, `storage_unavailable`, `execution_failed`.
7. `retryable` là boolean bắt buộc trong error response; lỗi deterministic (`invalid_schema`, `identity_mismatch`, `expired`, `unsupported_command`, `invalid_arguments`, `conflict`) không retry. Chỉ retry lỗi transient với cùng identity/request ID. Timeout không tự biến thành `failed`.

## Fixture files

- `v1/telemetry-valid.json`: payload ESP32 v1 hợp lệ theo DTO hiện tại.
- `v1/telemetry-invalid-humidity.json`: payload phải bị DTO từ chối vì humidity vượt miền.
- `v2/minute-log-valid.json`: log minute với identity, time, metrics, rain counter, epoch, calibration version và quality.
- `v2/minute-log-invalid-missing-sequence.json`: giống hệt minute log hợp lệ ngoại trừ việc thiếu `window_sequence`, để cô lập lỗi identity cần reject.
- `v2/minute-log-invalid-counter-decrease.json`: counter giảm trong cùng epoch; reject với `invalid_counter_range`.
- `v2/config-desired.json`: snapshot cấu hình đầy đủ, versioned.
- `v2/config-reported-applied.json`: firmware report đầy đủ sau khi persist và apply thành công.
- `v2/command-request.json`, `v2/command-response-completed.json`, `v2/command-response-failed.json`: phân biệt request, kết quả completed và lỗi failed.
- `v2/history-response.json`: fixed bucket/range và rainfall amount, không phải rain rate.

Các fixture v2 thể hiện semantics đã chốt cho P00; chúng chưa chứng minh implementation. Minute-log dùng bộ đếm mưa không đổi và `calibration_version`; `rainfall_mm` do backend suy ra, không nằm trong input. History mang amount theo bucket; rate trung bình là giá trị backend-derived tùy API. PR-01 vẫn phải bổ sung JSON Schema/validator và automated expected-outcome tests trước khi P04 bật publisher.
