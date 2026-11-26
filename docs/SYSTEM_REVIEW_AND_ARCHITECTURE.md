# Tham chiếu kiến trúc và review hệ thống IoT: FW, BE, App

Cập nhật: **26/11/2026, UTC+7**. Baseline source khảo sát: **master, commit 1d34a59**. Bổ sung kết quả đối chiếu/review ngày 26/11; các bổ sung vẫn là kế hoạch, chưa phải implementation.

**Vai trò tài liệu:** lưu kết quả khảo sát, quyết định kiến trúc, contract đích và traceability đầy đủ. Đây không phải checklist thực thi tuần tự. Roadmap ngắn và các kế hoạch triển khai theo từng đợt nằm tại [`SYSTEM_REVIEW_AND_IMPLEMENTATION_PLAN.md`](SYSTEM_REVIEW_AND_IMPLEMENTATION_PLAN.md) và [`plans/`](plans/). Các thiết kế trong tài liệu này chưa đồng nghĩa code, migration hay deploy đã được thực hiện. Tên bảng, field và API v2 là contract đích, không phải khẳng định chúng đã có trong repository.

## 1. Mục tiêu, phạm vi và quyết định đã chốt

### 1.1. Mục tiêu

- Một trạm có lịch sử liên tục khi thay board; biết nguồn thiết bị, lần lắp đặt và phiên khởi động của từng bản ghi.
- MQTT có định tuyến, phân quyền, retained và ACK đúng ngữ nghĩa cho từng chức năng.
- Đo/cảnh báo cục bộ nhanh; giảm lưu và truyền không cần thiết bằng log tổng hợp phút.
- Backend ghi idempotent, kiểm soát tải, xử lý mất mạng/DB lỗi và không báo thành công sai.
- Lịch sử chia mốc cố định, tổng hợp đúng đơn vị/thống kê; app chỉ sync khoảng cần thiết.
- App hiển thị local trước, không nhầm trạm, không xóa nội dung cũ trong mỗi lần refresh.
- Thay đổi từng bước, giữ tương thích firmware/app cũ và có thể rollback.

### 1.2. Quyết định đã được đồng ý

| Mã | Quyết định | Phạm vi thực hiện |
| --- | --- | --- |
| DEC-01 | EMQX không ghi trực tiếp Supabase | Backend là đường ghi của hệ thống; bỏ giả thuyết EMQX direct-write |
| DEC-02 | station_id khác device_id | Trạm là đối tượng quan trắc; ESP32 là phần cứng; MAC là thuộc tính |
| DEC-03 | Có lịch sử deployment | Thay board/điều chuyển không sửa nghĩa dữ liệu cũ |
| DEC-04 | ID hệ thống ổn định, không lấy MAC làm khóa trạm | Provision một device ID, giữ qua reboot; simulator không cần MAC thật |
| DEC-05 | ID thiết bị có trong topic và payload | Backend đối chiếu; credentials/ACL mới là căn cứ xác thực |
| DEC-06 | Chín mẫu topic chính | Live, log, availability, state, desired/reported config, command request/response, events |
| DEC-07 | Log lịch sử 60 giây | Tổng hợp cả phút; không chỉ giữ mẫu cuối phút |
| DEC-08 | Live 5 giây theo nhu cầu, có TTL | Bật trong phiên xem realtime hoặc burst có giới hạn; không lưu mọi live vào history |
| DEC-09 | Event gửi sau khi phát hiện chuyển trạng thái | Alarm/fault/recovery không đợi log phút; có dedup/debounce/hysteresis |
| DEC-10 | ESP-MQTT là hướng firmware; giữ MQTT.js ở BE | Pin toolchain và kiểm chứng tích hợp trước rollout |
| DEC-11 | Fixed buckets + API range + incremental local-first | Mặc định biểu đồ intraday 10 phút; summary theo ngày của trạm |
| DEC-12 | Desired/reported và operation ledger | Phân biệt broker ACK, lưu DB, nhận lệnh, lưu NVS và thực thi |
| DEC-13 | Baseline 25/11 chỉ lập kế hoạch | Mọi bước implementation chưa thực hiện tại thời điểm ghi baseline; roadmap/plan con hiện hành được index riêng |

Các tham số như dung lượng queue, retention, grace, timeout, mục tiêu latency được ghi rõ là cấu hình khởi đầu cần kiểm thử. Không đưa các quyết định kiến trúc đã đồng ý trở lại danh sách “chưa biết có nên làm hay không”.

### 1.3. Phạm vi đã khảo sát và giới hạn bằng chứng

Đã đối chiếu source FW, BE, Flutter, tests, simulator và cấu hình deploy. Probe các lượt trước dùng source/library trong bộ nhớ và mock; không ghi Supabase hay điều khiển board. SDK đã đọc metadata/header/symbol, chưa có bản ESP-MQTT migration build/run. Snapshot schema DB là ngày 24/11, chưa xác nhận live lại ngày 25/11.

Xác nhận EMQX không ghi trực tiếp DB đến từ người dùng. ACL/session limits/retention live, tải production, heap board, frame time/pin điện thoại và chịu mất điện vẫn cần đo. Hai BE local/cloud cùng subscribe vẫn có thể ghi trùng; đó là nguy cơ khác với direct-write của EMQX.

Các đính chính baseline: firmware đã merge partial config đúng, default rain_max trong code/NVS fallback hiện là 30 mm/h, đã có cảnh báo nhiệt độ thấp/độ ẩm và kiểm tra DHT tại local. Các thay đổi này không tự sửa NVS cũ, DB cũ hoặc đường FCM global.

## 2. Mô hình tham chiếu và lựa chọn cho dự án

| Hệ thống/chuẩn đã khảo sát | Nguyên tắc hữu ích | Cách áp dụng tại đây |
| --- | --- | --- |
| OGC SensorThings | Tách đối tượng, vị trí/lịch sử vị trí, sensor và observation | Tách station/device/deployment; chưa cần triển khai toàn bộ chuẩn |
| WMO/WIGOS | Định danh trạm gắn tính liên tục quan trắc; di chuyển cần đánh giá tác động | Thay board giữ station; chuyển địa điểm quan trắc đáng kể mặc định tạo station mới |
| AWS IoT Device Shadow | Desired/reported/delta, version và đồng bộ khi offline | Config snapshot/version, reported sau lưu/áp dụng; không cần chuyển sang AWS |
| ThingsBoard | Identity từ credentials; attributes khác RPC; request ID nối command/response | Registry/ACL, config khác command, operation ledger |
| Home Assistant MQTT | Tách state/command/availability và dùng birth/LWT | Availability retained riêng device, state reported khác kết nối |
| ESPHome | Tách đọc sensor, tổng hợp theo thời gian, thay đổi và heartbeat | Log phút + live theo nhu cầu + event; không sao chép nguyên cấu hình nền tảng |
| PostgreSQL / Timescale | Fixed time bin, aggregate/rollup dùng lại cho nhiều client | SQL range trước, rollup khi cần; không giả định Supabase có Timescale |
| Flutter offline-first | Repository hợp nhất local/remote; local có thể hiển thị trước mạng | Cache theo trạm/series, sync metadata và UI từng phần |

Đây là lựa chọn thiết kế cho quy mô hiện tại; không có tiêu chuẩn chung bắt mọi trạm gửi đúng 60 giây. So sánh và nguồn chính thức nằm ở cuối tài liệu.

## 3. Định danh trạm, thiết bị và lịch sử lắp đặt

### 3.1. Ý nghĩa và vòng đời

| Định danh | Đại diện | Đổi khi nào? | Nơi dùng |
| --- | --- | --- | --- |
| station_id | Điểm/trạm quan trắc logic | Tạo trạm mới theo nghiệp vụ | App, quyền truy cập, history và station policy |
| device_id | ESP32/thiết bị cụ thể | Thay phần cứng | MQTT topic/credentials, diagnostics |
| deployment_id | Một lần device được lắp tại station | Thay board hoặc điều chuyển | Attribution dữ liệu, config/command target |
| boot_id | Phiên khởi động | Reboot | Chống nhầm phiên, availability, dedup |
| sequence/window_sequence | Thứ tự trong boot theo stream | Tăng khi tạo bản tin mới | Retry/dedup; không dùng MQTT packet ID |
| factory_mac | Thuộc tính nhận diện phần cứng | Theo hardware; không tự đổi thành ID trạm | Provision/đối chiếu, không phải secret |
| request_id/event_id | Operation/sự kiện nghiệp vụ | Mỗi operation/event mới | Retry, audit, phản hồi |

ID mới dùng UUID do hệ thống cấp; ví dụ sta-001/dev-001 trong tài liệu chỉ là cách viết ngắn để dễ đọc. Firmware không sinh lại device_id mỗi lần boot hoặc chỉ vì flash lại application. Factory reset identity cần luồng reprovision có quyền, không tự tạo device mới ở mọi lần reconnect.

### 3.2. Vì sao không dùng MAC làm station ID

- Thay ESP32 không được làm app mất liên kết lịch sử trạm.
- Điều chuyển board không được làm dữ liệu cũ đổi vị trí theo metadữ liệu mới.
- Simulator trong tools không có factory MAC thật.
- MAC theo Wi-Fi STA/SoftAP/Bluetooth có thể khác; MAC interface có thể chỉnh được.
- MAC/ID là định danh, không chứng minh ai có quyền publish hoặc sở hữu thiết bị.

MAC-derived device ID đầy đủ có thể dùng ở prototype, nhưng hướng đã chọn là ID hệ thống độc lập + factory MAC được xác minh lúc provision. Không cắt vài byte cuối làm ID chung; không hash MAC rồi coi đó là authentication.

### 3.3. Trạm và deployment

~~~text
station sta-001: Sơn Trà

dep-001: dev-001 từ 01/11 đến trước 21/11
dep-002: dev-002 từ 21/11 trở đi

App tiếp tục xem sta-001.
History giữ được device/deployment nguồn từng khoảng.
~~~

Quy tắc:

1. Đổi tên/mô tả hoặc sửa tọa độ nhập sai không tự đổi ID; có audit metadata.
2. Thay board tại cùng trạm giữ station_id, đóng deployment cũ và mở deployment mới.
3. Đổi sang địa điểm có điều kiện quan trắc khác đáng kể mặc định tạo station mới. Trường hợp giữ ID phải có lý do và metadata lịch sử rõ; không tự động giữ vì cùng board.
4. Trong phiên bản đầu, một trạm có tối đa một device chính active, một device có tối đa một deployment active. Nếu cần nhiều sensor/gateway về sau thì mở rộng contract.
5. Khoảng deployment dùng [valid_from, valid_to); việc đóng/mở và cập nhật active target phải nằm trong transaction.
6. Late log gán theo deployment tại thời điểm đo. Không dùng device.station_id hiện tại cho toàn bộ backlog.
7. Khi clock chưa tin cậy hoặc khoảng log cắt qua lúc đổi deployment, không đoán: cần split, quarantine hoặc gắn attribution không chắc chắn.
8. Command theo station phải resolve deployment hiện tại trên BE; khi queued lâu hoặc reassign, kiểm tra lại expected deployment/boot trước publish/thực thi.

### 3.4. Dữ liệu station/device và chính sách cấu hình

Station chứa code/name/description, lat/lon/elevation, timezone, trạng thái, policy cảnh báo. Device chứa loại physical/simulator, MAC đã xác minh, model, firmware, lifecycle và tham chiếu credentials. Deployment ghi liên kết và hiệu lực.

Ngưỡng quan trắc là policy của station, được triển khai xuống device đang active. Cấu hình phần cứng/calibration/firmware thuộc device. Buzzer/auto_warning cần phân biệt desired station policy với trạng thái thực tế của board. Khi thay board, lấy policy station triển khai lại, không lấy default mới để overwrite mọi tùy chỉnh cũ.

Server xác thực mapping device → deployment → station; station_id/deployment_id do thiết bị gửi chỉ là thông tin đối chiếu, không phải quyền tự khai.

## 4. Kiến trúc luồng dữ liệu đích

~~~mermaid
flowchart LR
    Sensors[ESP32 sensors / local alarm] --> Agg[Minute accumulator + bounded history buffer]
    Sensors --> Live[Live snapshot + events]
    Agg --> Broker[EMQX]
    Live --> Broker
    Broker --> Ingest[BE validate / identity / dedup]
    Ingest --> DB[(Supabase minute logs + registry)]
    DB --> Rollup[Fixed buckets / daily summaries]
    Ingest --> Latest[Latest / state / event processing]
    Latest --> FCM[FCM theo policy]
    Latest --> WS[Authorized foreground WebSocket]
    Rollup --> REST[REST range / summary]
    REST --> Cache[(App local cache + sync metadata)]
    WS --> Cache
    Cache --> UI[App UI theo station]
    UI --> Ops[BE config / command operations]
    Ops --> Broker
    Broker --> Sensors
~~~

- BE là nơi ghi Supabase; EMQX không ghi DB trực tiếp.
- Live cập nhật latest, không insert mỗi snapshot vào history.
- Log phút là nguồn lịch sử v2; event và reported có storage/semantics riêng.
- Lịch sử app theo station; MQTT theo device; deployment nối hai lớp.
- Latest có thể được cache trong BE/DB theo cadence phù hợp; không yêu cầu ghi một row history cho mỗi live.
- Nếu raw log đã commit nhưng aggregate lỗi, worker retry/rebuild aggregate; không yêu cầu FW tạo sample mới.
- WebSocket không thay REST reconcile; app mất kết nối vẫn đọc cache và backfill qua range API.

## 5. MQTT: toàn bộ topic, ACL và trách nhiệm

### 5.1. Namespace đã chọn

Prefix production: adht/weather/{D}, với D là device_id, R là request_id. Dev/staging dùng namespace hoặc broker/credentials tách biệt; không chạy BE dev ghi DB production cùng consumer cloud.

ID nằm trong topic và envelope; tên/vị trí trạm không nằm trong topic. Schema có version trong payload. Chưa đổi toàn prefix sang namespace khác chỉ để thêm chữ v2.

### 5.2. Chín mẫu topic chính

| Mã | Topic | Producer → consumer | QoS đích | Retain | Nội dung và tác dụng |
| --- | --- | --- | --- | --- | --- |
| T01 | adht/weather/{D}/telemetry/live | FW → BE | 0 | Không | Snapshot current khi live lease/burst đang active; cập nhật latest/WS |
| T02 | adht/weather/{D}/telemetry/log | FW → BE | 1 | Không | Tổng hợp interval 60s, có identity, quality/counter; nguồn history |
| T03 | adht/weather/{D}/availability | FW + broker LWT → BE | 1 | Có | Online/offline theo device và phiên kết nối |
| T04 | adht/weather/{D}/state/reported | FW → BE | 1 | Có | Mode/output còi/LED, snooze, sensor health, boot/config version |
| T05 | adht/weather/{D}/config/desired | BE → FW | 1 | Có | Snapshot đầy đủ sau merge, có version/deployment |
| T06 | adht/weather/{D}/config/reported | FW → BE | 1 | Có | Snapshot/version đã lưu và áp dụng, kết quả reconciliation |
| T07 | adht/weather/{D}/command/request/{R} | BE → FW | 1 | Không | Command một lần, expected deployment/boot khi cần, expiry |
| T08 | adht/weather/{D}/command/response/{R} | FW → BE | 1 | Không | Accepted/completed/failed; cùng request ID |
| T09 | adht/weather/{D}/events | FW → BE | 1 | Không | Alarm/fault/recovery/snooze/counter reset có event ID |

Chín mẫu là chín loại route, không phải tạo một topic mới cho từng sensor, từng threshold hoặc từng command. Telemetry fields đi chung theo cadence/semantics. PubSubClient hiện chỉ publish QoS0; QoS1 ở bảng là mục tiêu sau migration ESP-MQTT.

### 5.3. Producer/consumer và ACL chính xác

| Principal | Được publish | Được subscribe |
| --- | --- | --- |
| Device D | T01/T02/T03/T04/T06/T08/T09 của D | T05/T07 của D |
| BE service | T05/T07 theo scope service | T01/T02/T03/T04/T06/T08/T09 của các device được quản lý |
| App | Không kết nối MQTT trực tiếp | Không; dùng REST/WS đã authorize |
| Simulator | Như device, riêng namespace/credentials môi trường test | Chỉ ID của nó |

Device không được publish config/desired hoặc command request, kể cả nằm dưới prefix của chính nó. Generic allow-write toàn prefix device là chưa đủ. Client ID không phải secret; phải gắn credentials/certificate với device và ACL. Chặn wildcard không được phép, giới hạn payload/rate và thu hồi device đã retire. Credentials không ghi vào document/log.

MQTT subscriber thông thường không mặc định được nhận identity publisher đáng tin cậy. Topic/payload khớp không thay kiểm tra ACL; không tin trường username/client_id do payload tự khai.

### 5.4. Availability, reported state và reconnect

- T03 online chỉ sau khi transport sẵn sàng và subscription cần thiết được xác nhận; lỗi SUBACK không được coi fully ready.
- Last Will cấu hình lúc connect, không biết trước disconnect time thực. BE dùng received_at và session metadata đúng nghĩa.
- T03 có connection_id mới cho mỗi lần reconnect, ngoài boot_id; một boot có thể có nhiều kết nối. LWT thuộc connection cũ không được làm offline connection mới.
- Retained availability/state/report là snapshot cuối; đối chiếu connection/boot, revision và tuổi dữ liệu trước khi áp lên phiên hiện tại.
- Reconnect gửi birth/state, đồng bộ desired config và reported version; không gửi lại command cũ hết hạn.
- T04 tối thiểu gửi sau boot/reconnect và khi mode/output/health/snooze đổi; dữ liệu uptime/RSSI có thể piggyback log/live, tránh heartbeat thừa.
- Không phát state cho mọi cạnh nhấp nháy LED/còi; report mode và trạng thái alarm ổn định, command result đủ giải thích output.
- Snooze chỉ tạm ngắt còi theo hành vi hiện tại; không đồng nghĩa alarm đã clear, không tự tắt FCM.
- LED manual mode có thể bị alarm priority ảnh hưởng đầu ra; response/state phân biệt requested mode và effective output.

### 5.5. Config và command hiện có

| Chức năng hiện tại | Route đích | Quy tắc |
| --- | --- | --- |
| temp_max/temp_min/humi_max/wind_max/rain_max | T05/T06 | Một snapshot 7 trường, không một topic/trường |
| auto_warning/buzzer lâu dài | T05/T06 | Boolean persistent; khác lệnh thử còi |
| LED | T07/T08, kết quả T04 | Chuẩn hóa set on/off/auto, hạn chế toggle |
| Thử còi | T07/T08 | Duration có min/max; không block task mạng |
| reboot/reset alias | T07/T08 + T03/T04 sau boot | Accepted trước restart, xác nhận boot mới; không giả completed trước reboot |
| reset_rain | T07/T08 + T09/T02 | Sensor task reset và tăng counter epoch |
| Nút SET snooze | Local + T04/T09 | Không cần command MQTT cho mỗi lần bấm |
| Nút SET đổi trang OLED | Local | Không phát mọi click nếu không có nhu cầu audit |
| Bật phiên live | T07/T08; stream T01 | Lệnh transport mới phục vụ chức năng đã chốt, có TTL; không lưu vào config persistent |

T09 bao gồm ALARM_RAISED/CLEARED, SENSOR_FAULT/RECOVERED, SNOOZE_CHANGED, RAIN_COUNTER_RESET và sự kiện vận hành cần thiết. Có event ID/occurred_at/config version/quality; chỉ phát transition và reminder theo policy, không mỗi vòng task.

T05 retained phải là snapshot đầy đủ đã merge; không giữ patch cuối cùng. T07/T08/T09 không retain để tránh thực thi lại khi subscriber mới vào.

### 5.6. Chức năng không cần MQTT topic mới

CRUD station/name/location/deployment là REST/DB; latest/history/daily summary là REST; forecast là BE gọi provider; đăng ký FCM token là REST; theme/tab/chart và đổi trang OLED là local. FCM topic là namespace Firebase, không phải EMQX.

Tùy chọn nâng bảo đảm lịch sử: T10 adht/weather/{D}/telemetry/ack, BE → FW, QoS1, không retain. Chỉ thêm khi chốt yêu cầu device giữ log tới DB commit. Nó chưa thuộc 9 topic bắt buộc; triển khai T02 QoS1 không được quảng cáo đã có T10/end-to-end DB ACK.

## 6. Chu kỳ đọc, gửi và lưu

### 6.1. Cadence đã chốt và lý do

| Hoạt động | Chu kỳ/chính sách | Ý nghĩa |
| --- | --- | --- |
| Thu xung mưa/gió | Interrupt như hiện tại | Không phụ thuộc upload |
| DHT | Khoảng 2,5s | Giữ baseline đọc hợp lệ |
| Tính gió baseline | 5s như hiện tại | Phân biệt peak mẫu với gust chuẩn khí tượng |
| OLED/local alarm | Giữ task nhanh hiện tại | Không đợi cloud hay log phút |
| T02 log | 60s, cửa sổ cố định | Tổng hợp cả phút |
| T01 live | 5s khi có lease/burst | Realtime, không history insert mặc định |
| T09 event | Sau phát hiện/qualify transition | Không đợi 60s; có debounce/hysteresis |
| T03 availability | Connect/LWT/disconnect có kiểm soát | Không dùng timer gửi online mỗi 5s |
| T04 state | Boot/reconnect/thay đổi quan trọng | Không spam xung nháy hardware |
| T06 config report | Apply thành công/reconcile | Versioned, không gắn nhịp 60s |
| T08 command result | Theo tiến trình command | Không phải telemetry periodic |
| App history | Pull khi có phần thiếu/correction | Không polling nền; fixed cutoff |
| App current | REST refresh hoặc foreground live WS | Có freshness/source rõ |

60s là baseline đã đồng ý cho dự án, không là tiêu chuẩn chung. Cảnh báo local tiếp tục hoạt động khi mất mạng; network latency không có SLA khi offline.

### 6.2. So sánh định lượng và ngữ nghĩa

| Chu kỳ định kỳ | Bản tin/ngày/device | Nhận xét |
| --- | --- | --- |
| 5s | 17.280 | Dễ lãng phí khi mỗi snapshot thành một DB insert |
| 10s | 8.640 | Gần realtime; vẫn nhiều hơn nhu cầu lịch sử |
| 30s | 2.880 | Có thể cấu hình sau khi đo; không là mặc định đích |
| 60s | 1.440 | Baseline log phút |
| 5 phút | 288 | Chậm nếu dùng cả cho alarm/current; chưa chọn |

Một batch 12 mẫu raw 5s/phút chỉ giảm packet xuống 1.440/ngày; DB vẫn 17.280 mẫu/ngày. Một log tổng hợp phút giảm số bản ghi lịch sử xuống khoảng 1.440/ngày nhưng không giữ mọi raw sample. Chế độ raw phục vụ kiểm chuẩn/nghiên cứu có thể thêm có thời hạn, không chạy mặc định.

Giảm khoảng 12 lần chỉ đúng cho phần gửi/lưu periodic history khi chuyển từ một insert mỗi 5s sang một log mỗi phút. Event, reported và các phiên live cộng thêm traffic; không tuyên bố toàn hệ thống chắc chắn giảm đúng 12 lần.

### 6.3. Minute accumulator

- UTC interval [start,end), ví dụ [10:20:00,10:21:00) giờ trạm; gửi sau đóng interval với jitter nhỏ có giới hạn.
- Upload jitter không thay bucket timestamp. Có thể bắt đầu thử 0–5s; điều chỉnh grace server theo đo thực tế.
- Mỗi metric giữ latest, sum/count/min/max và coverage hợp lệ. Không lấy trung bình lại các mean thiếu trọng số.
- Counter/tip mưa, epoch reset và quality giữ đủ để tính amount. Bộ đếm cách xa không tự cho biết phân bố chính xác giữa các phút.
- Clock chưa đồng bộ, reboot giữa phút hoặc deployment đổi giữa phút phải tạo partial/unsynchronized record theo contract; không tạo timestamp UTC chắc chắn bằng suy đoán.
- Sau boot, gửi state và latest hợp lệ khi có, không đợi đủ phút để UI thấy thiết bị; trước DHT valid không phát sentinel 0 như số đo thật.
- Reset rain/đổi deployment chia hoặc đóng partial interval với provenance để không trộn hai epoch/nguồn trong một summary.
- Packet tổng hợp có thể vượt buffer JSON 384B/MQTT 512B hiện tại. FW và BE phải đo kích thước max, cấu hình cap và xử lý fragmentation, không chỉ sửa hằng số 5000 thành 60000.

### 6.4. Phiên live có thời hạn

App user chủ động mở live cho station; BE authorize, resolve active deployment và quản lý lease/watchers. Chỉ một stream T01 cho mỗi device dù nhiều viewers.

Tham số khởi đầu: lease tối đa 120s/lần cấp; BE chỉ gia hạn khi còn foreground viewer được phép và không vượt giới hạn phiên. Gia hạn qua BE/WS lifecycle, không thêm HTTP polling nền ở app. Viewer cuối rời thì BE yêu cầu stop; nếu stop thất lạc FW tự hết TTL.

Lệnh set_live_mode qua T07 có enabled, interval_s=5 và ttl_s, kèm identity/expiry. Không giữ live mode trong NVS; reboot không làm board gửi nhanh vô hạn. Burst tự động sau alarm có cap/duration cấu hình và không thay cadence T02. Disconnect app, logout, đổi station hoặc thu hồi quyền phải release lease.

### 6.5. Sự kiện cảnh báo

Dùng qualified transition và hysteresis/debounce theo loại sensor; “gửi ngay” là sau phát hiện hợp lệ, không cam kết 0ms. Cần tránh hai cực: spam mỗi sample hoặc trì hoãn đến log phút. Reminder có cooldown riêng, baseline có thể theo 5 phút hiện tại sau khi đánh giá.

BE xác thực event, source quality, config version và policy FCM; không tin event để bỏ qua phân quyền/validation. Event replay quá cũ không được gửi push như vừa xảy ra. Alarm local, snooze local và cloud notification là ba trạng thái riêng.

## 7. Contract payload và tính đúng dữ liệu

### 7.1. Envelope chung

Protocol schema_version=2. Các stream có type/identity rõ; các ID ngắn ở ví dụ không phải định dạng UUID bắt buộc thực tế. Thời gian truyền ISO8601 UTC; thời gian tương đối có hậu tố ms/s rõ.

~~~json
{
  "schema_version": 2,
  "type": "minute_log",
  "device_id": "dev-001",
  "deployment_id": "dep-002",
  "boot_id": "boot-identifier",
  "window_sequence": 123,
  "interval_start": "2026-11-25T03:20:00Z",
  "interval_end": "2026-11-25T03:21:00Z",
  "clock_quality": "synchronized",
  "metrics": {
    "temperature": {
      "unit": "degC",
      "sum": 720.0,
      "count": 24,
      "min": 29.0,
      "max": 31.0,
      "latest": 30.2
    }
  },
  "rain": {
    "counter_epoch": 0,
    "tip_count_start": 40,
    "tip_count_end": 42
  },
  "quality": {
    "dht_valid_count": 24,
    "coverage_ms": 60000
  }
}
~~~

Ví dụ chỉ hiển thị temperature/rain để đọc được; schema đầy đủ phải có humidity, wind stats, rate và quality tương ứng. Không tự coi count=24 là luôn đủ nếu sensor cadence thay đổi. Mỗi metric có valid count/coverage, không dùng một cờ chung để che lỗi một sensor.

### 7.2. Identity, thời gian và dedup

- Log identity: device_id + boot_id + window_sequence; event/command có identity riêng. Resend giữ nguyên identity/payload, không tăng sequence vì retry.
- Live sequence tách khỏi log hoặc có stream discriminator; MQTT packet ID không dùng làm business identity.
- BE gán received_at và kiểm tra deployment tại observed interval; không dùng received_at thay observed_at cho backlog.
- Một identity khác payload là conflict cần audit/quarantine; không âm thầm overwrite.
- Clock lựa chọn triển khai: ưu tiên SNTP có quality để chia phút/TLS; nếu chưa sync có mode unsynchronized và buffer/reconcile rõ. NTP không là lý do tắt CA validation.
- Timestamp lỗi/thiếu không được parser app đổi thành now. Cần null/no-data hoặc error có contract.
- station_id được server xác định theo deployment; nếu envelope khai sai phải từ chối/đánh dấu, không sửa lịch sử theo mapping hiện tại.

### 7.3. Mưa, gió và summary

Mưa: tách rain_rate mm/h khỏi rainfall_mm. Với thông số cơ khí hiện tại, mỗi tip khoảng 0,631712 mm; calibration phải version hóa. Counter epoch đổi khi reset trong boot; boot mới không bị coi là counter chạy liên tục. Không cộng rate thành amount, không chặn delta âm về 0 rồi giấu reset.

Nếu chỉ có counter đầu/cuối và thiếu baseline/coverage, amount phải partial/unknown theo quy tắc, không tự biết từng phút đã mưa bao nhiêu. Lịch sử rate-only cũ không khôi phục chính xác amount; estimation phải có nhãn riêng.

Gió: threshold wind_max trong config không trùng nghĩa gust trong telemetry. Firmware hiện peak trên mẫu 5s/cửa sổ 10 phút, không tự được gọi gust chuẩn 3-second mean của khí tượng. Schema đặt tên/cửa sổ rõ. Nếu yêu cầu chuẩn khí tượng, đó là bước lấy mẫu/calibration riêng, không chỉ đổi MQTT cadence.

Daily summary lấy sum/count/min/max từ stats hợp lệ, không tính min/max từ mean theo giờ hoặc trung bình không trọng số của các mean. Nếu yêu cầu time-weighted average phải có coverage/thời lượng; sample-weighted và time-weighted không được dùng lẫn.

### 7.4. Completeness và correction

Phân biệt ba thứ: khoảng đã xử lý query thành công; khoảng đủ tuổi để phục vụ; mức đầy đủ dữ liệu vật lý. Đã qua 10:40 không chứng minh bucket 10:30–10:40 có đủ mẫu.

Mỗi aggregate có sample_count/coverage/quality, aggregation_version và revision. Missing là missing, không phải giá trị 0. Late log cập nhật các bucket/day liên quan và có cơ chế client nhận correction.

### 7.5. Config desired và reported

T05 là snapshot đầy đủ, không phải patch được App gửi. BE cấp version và gắn deployment; token/credentials không nằm trong snapshot.

~~~json
{
  "schema_version": 2,
  "device_id": "dev-001",
  "deployment_id": "dep-002",
  "config_version": 12,
  "config": {
    "temp_max": 38.0,
    "temp_min": 10.0,
    "humi_max": 90.0,
    "wind_max": 15.0,
    "rain_max": 30.0,
    "auto_warning": true,
    "buzzer": true
  }
}
~~~

T06 báo config_version, deployment, boot, kết quả persist/apply và snapshot đã áp dụng. Nếu persist fail, không gửi status applied/persisted=true. Report cũ không được làm desired version mới trông như đã hoàn tất.

### 7.6. Command và response

Ví dụ trên T07 với R=op-001:

~~~json
{
  "schema_version": 2,
  "device_id": "dev-001",
  "deployment_id": "dep-002",
  "request_id": "op-001",
  "command": "buzzer_test",
  "args": { "duration_ms": 500 },
  "issued_at": "2026-11-25T03:20:00Z",
  "expires_at": "2026-11-25T03:20:15Z"
}
~~~

T08 với cùng R trước hết có thể báo accepted, sau đó completed/failed. Payload completed tối thiểu:

~~~json
{
  "schema_version": 2,
  "device_id": "dev-001",
  "deployment_id": "dep-002",
  "boot_id": "boot-identifier",
  "request_id": "op-001",
  "status": "completed",
  "result": { "duration_ms": 500 }
}
~~~

Tên command v2 chuẩn hóa set_led, buzzer_test, reboot, reset_rain và set_live_mode; BE adapter ánh xạ tên/arg legacy. Duration/TTL/expiry có giới hạn, identity không thay đổi khi retry.

### 7.7. Reported state và event

T04 lưu snapshot vận hành, phân biệt mode đã yêu cầu với đầu ra do alarm priority:

~~~json
{
  "schema_version": 2,
  "device_id": "dev-001",
  "deployment_id": "dep-002",
  "boot_id": "boot-identifier",
  "state_sequence": 82,
  "reported_at": "2026-11-25T03:20:00Z",
  "config_version": 12,
  "led_mode": "auto",
  "led_output": false,
  "buzzer_active": false,
  "alarm_snoozed": true,
  "snooze_remaining_s": 120,
  "dht_valid": true
}
~~~

Snooze remaining là giá trị tại reported_at, không đứng yên 120s mãi trong retained snapshot. Khi clock chưa sync, report có uptime/clock quality tương ứng và BE ghi received_at.

T09 alarm event có cấu trúc tối thiểu:

~~~json
{
  "schema_version": 2,
  "device_id": "dev-001",
  "deployment_id": "dep-002",
  "boot_id": "boot-identifier",
  "event_id": "event-023",
  "event_type": "ALARM_RAISED",
  "alarm_type": "HIGH_TEMP",
  "occurred_at": "2026-11-25T03:20:00Z",
  "config_version": 12,
  "measurement": { "value": 39.4, "threshold": 38.0, "unit": "degC" },
  "quality": { "valid": true, "age_ms": 800 }
}
~~~

BE phải xác thực context và policy, không cho phép một event tự khai ID khác để phát FCM. Retry giữ event_id; event clear liên kết cùng alarm instance để tránh clear nhầm lần cảnh báo mới.

## 8. Thiết kế BE/DB và HTTP API

### 8.1. Mô hình dữ liệu logic và tương thích bảng hiện có

Không drop/recreate devices đang có. Bước audit xác định FK/index trước khi chọn migration vật lý; mô hình dưới là đích bắt buộc về ý nghĩa, không ép đổi primary key live trong một lần.

| Nhóm | Bảng/đối tượng đích | Nội dung |
| --- | --- | --- |
| Registry | stations | UUID, code/name/location/timezone, lifecycle, audit metadata |
| Registry | devices | UUID mới, legacy device_id alias giữ tương thích, kind, factory MAC xác minh, hardware/firmware |
| Binding | device_deployments | Device UUID ↔ station UUID, valid interval, assignment revision |
| History | weather_minute_logs | Log v2 idempotent, deployment, observed interval, stats/counter/quality |
| Aggregate | weather_buckets / weather_daily_summaries | Fixed key/version/revision, stats và coverage |
| Current | device/station latest + reported state | Cache/snapshot, freshness/source; không phải raw history |
| Configuration | station desired + device reported | Version, deployment binding, persist/apply status |
| Operations | command/config operation + publish outbox | Actor, request/version, expiry, retry/status/result |
| Events | device/station events | Event ID, occurred/received time, alarm/fault/replay metadata |
| Access | station access scope | Viewer/operator/admin hoặc mapping tương đương của identity provider |

Đề xuất migration nhẹ cho bảng devices hiện có: thêm UUID unique làm identity v2, giữ cột text device_id hiện tại như alias legacy trong thời gian chuyển đổi; reference mới dùng UUID. Không đổi PK hoặc đoán factory_mac từ giá trị seed khi chưa audit. Simulator được kind=simulator, MAC phần cứng optional theo schema mới; constraint legacy được điều chỉnh bằng migration được kiểm thử, không chạy SQL cũ bất chấp model mới.

Registry one-active-device-per-station và one-active-deployment-per-device được bảo đảm bằng transaction/constraint phù hợp. Không cascade-delete history khi retire station/device.

### 8.2. Phân tách API station và device

App thao tác nghiệp vụ theo station. Device endpoints dùng quản trị/provision/diagnostics hoặc adapter legacy. Không để mọi màn hình tiếp tục gọi station là device.

| API đích | Quyền/semantics | Consumer |
| --- | --- | --- |
| GET /api/stations | Danh sách được phép, pagination | App catalogue |
| GET /api/stations/:id | Metadata, active deployment và freshness summary theo quyền | App detail |
| POST/PATCH station metadata | Admin, validate tọa độ/timezone, audit | Quản trị |
| POST /api/stations/:id/deployments | Admin, transactional reassignment | Quản trị |
| GET /api/stations/:id/weather/latest | Current + observed/received/source/quality | Dashboard |
| GET /api/stations/:id/weather/history | from/to/resolution, range/points cap | Intraday/reconcile |
| GET /api/stations/:id/weather/daily | Calendar range/timezone, revisions, today partial | 7 ngày |
| GET /api/stations/:id/config | Desired/reported/status/version | Settings |
| PATCH /api/stations/:id/config | Expected version, patch → full validate | Settings |
| POST /api/stations/:id/commands | Operator, deployment target, expiry, idempotency | Điều khiển |
| GET /api/operations/:id | Status/result theo quyền | App reconciliation |
| POST/DELETE live sessions | Authorized viewer, lease lifecycle | Foreground live |
| WS station subscribe/unsubscribe | Auth + rooms theo station, revoke/logout xử lý | Foreground updates |
| Devices provision/retire/diagnostics | Admin, không coi MAC là secret | Quản trị |
| Notifications register-token | Auth/device installation binding theo policy | App FCM |

Tên endpoint là contract dự kiến có thể chỉnh nhất quán trước implementation; semantics không thay đổi. Old /devices và weather?device_id được adapter resolve alias, giữ response legacy có thời hạn; API v2 không giả dùng UUID station trong field device_id.

POST /telemetry hiện stub: không dùng như đường ingest thứ hai theo mặc định. Đề xuất disable rõ hoặc chỉ mở adapter có auth, cùng validation/dedup pipeline nếu thật sự cần simulator/webhook. Forecast hiện stub: trả feature unavailable rõ cho tới khi hoàn thiện provider; đây không là lý do tạo MQTT topic forecast.

### 8.3. Ingestion và ACK

Tách handler cho live/log/state/config-result/command-result/event, không chuyển tất cả vào CreateTelemetryDto/saveTelemetry hiện tại.

- Live: validate + authorize + quality → cập nhật current nếu observed time/sequence mới hơn → WS theo quyền; không insert history.
- Log: validate → binding/time attribution → unique identity → commit log → cập nhật/retry aggregate → metrics. Conflict/invalid được phân loại, không báo persist thành công.
- Event: idempotent lưu/đánh giá policy; replay cũ không thành alarm mới.
- Report/result: khớp request/version/deployment, không ACK một operation khác hoặc phiên cũ.
- Một message chỉ xử lý nghiệp vụ một lần; không xử lý ở cả message listener và override handleMessage.
- Dùng điểm ACK/backpressure phù hợp MQTT.js; ban đầu ưu tiên durable log pipeline tuần tự có timeout/giới hạn hơn concurrency không giới hạn. Nếu tăng concurrency phải kiểm chứng ordering/dedup/ACK và per-device policy.
- Broker ACK cho publisher và subscriber là hai chặng; DB commit là chặng khác. Không mô tả QoS1/2 là exactly-once business.
- Session backend có client ID ổn định, persistent khi broker hỗ trợ, resubscribe/session expiry/quota được audit. Không ACK trước DB chỉ vì đã thêm một item vào RAM queue rồi coi đó là durable.
- Poison message không được khóa vô hạn luồng; lỗi vĩnh viễn phải được quarantine/ghi nhận có giới hạn, lỗi tạm thời retry theo policy.

Không đưa Kafka/Redis vào chỉ để hoàn tất kế hoạch. Nếu tải/độ bền cần durable queue riêng, có gate đo và PR riêng. DB outbox cho command/config là trạng thái nghiệp vụ có thể retry, khác hàng đợi telemetry tùy chọn.

### 8.4. Auth, validation, liveness và readiness

Áp authn/authz cho REST/WS, quyền viewer/operator/admin theo station; firmware có credentials riêng và CA verification. RLS không chặn backend public dùng service-role, CORS cũng không thay auth.

Validate ID, command enum/args và config sau merge. Reject empty patch/null không hợp lệ; temp_min ≤ temp_max, humidity 0–100, wind/rain không âm, finite/limits theo sensor. Dữ liệu cũ ngoài miền được audit trước migration, không tự sửa hàng loạt.

Health liveness giữ nhẹ; readiness tách broker connected, SUBACK cần thiết, ingest/DB state và freshness metrics. Không đổi health thành restart loop khi chỉ broker tạm ngắt.

## 9. History theo mốc chẵn và cache app

### 9.1. Contract bucket/range

- Interval [from,to), origin cố định, UTC lưu trữ; timezone station quyết định calendar day. Trạm Việt Nam mặc định Asia/Ho_Chi_Minh.
- Intraday baseline 10 phút, dữ liệu từ 00:00 ngày station đến cutoff sẵn sàng; daily là hôm nay và 6 ngày lịch trước, không rolling 168 giờ giả thành 7 ngày lịch.
- Response có server_time, served_from/through, available_through theo policy, aggregation_version, revision và quality/coverage từng bucket.
- Pagination có ordering/cursor/snapshot ổn định; giới hạn range/points; không dùng OFFSET trên tập đang đổi như một bảo đảm completeness.
- Query aggregate trong PostgreSQL với index theo station/deployment/time. SQL range là bước đầu; rollup incremental thêm khi baseline yêu cầu.
- ETag là tối ưu thêm, không thay query đúng; tính ETag bằng full scan vẫn tốn DB.

Ví dụ minh họa response v2 cho request range tới 03:30Z (10:30 giờ trạm):

~~~json
{
  "station_id": "sta-001",
  "timezone": "Asia/Ho_Chi_Minh",
  "resolution": "10m",
  "aggregation_version": 2,
  "server_time": "2026-11-25T03:31:00Z",
  "served_from": "2026-11-25T03:20:00Z",
  "served_through": "2026-11-25T03:30:00Z",
  "available_through": "2026-11-25T03:30:00Z",
  "next_cursor": null,
  "points": [
    {
      "bucket_start": "2026-11-25T03:20:00Z",
      "bucket_end": "2026-11-25T03:30:00Z",
      "revision": 3,
      "temperature": { "mean": 30.0, "min": 29.0, "max": 31.0, "count": 240 },
      "rainfall_mm": 1.263424,
      "quality": { "coverage_ratio": 1.0, "state": "observed" }
    }
  ]
}
~~~

Đây là fixture thiết kế, không phải dữ liệu live. Coverage 1.0 mô tả phạm vi quan sát theo contract, không bảo đảm không có sai số cảm biến hoặc không bao giờ có correction. Response khoảng trống vẫn có served_through nhưng points rỗng/missing; App không tạo nhiệt độ 0. Với pagination, chỉ chốt coverage toàn khoảng khi các page và dữ liệu local đã commit đúng.

### 9.2. Đồng bộ chỉ phần thiếu

Ví dụ giờ station, cache đã commit các interval đến 10:30:

| Sự kiện | BE/App phải làm |
| --- | --- |
| Refresh 10:34 hoặc 10:38 | Đọc cache, không history request nếu coverage đủ và chưa có correction cần xử lý |
| 10:40 nhưng log phút/aggregate chưa qua grace | Giữ synced-through=10:30, không giả complete |
| Cutoff 10:40 đã phục vụ được | Lấy [10:30,10:40), cộng lookback nếu policy yêu cầu |
| App offline đến 12:15 | Backfill tất cả khoảng thiếu trong retention, không chỉ bucket cuối |
| Khoảng không có mẫu | Ghi queried coverage + missing, không hỏi lại vô hạn |
| Cache trống giữa bucket | Bootstrap phạm vi cần, không skip vì chưa có mốc mới |
| Rows ghi local lỗi hoặc page sau fail | Không advance cursor/coverage quá phần commit đúng contract |
| Cache bị evict hoặc resolution/version đổi | Invalidate coverage tương ứng trước sync |

Server quyết định cutoff dựa grace/processing state. Grace khởi đầu để đo có thể 15–30s, không là SLA. Với upload jitter 0–5s và hệ nhỏ, phải đo p95/p99 ingest/aggregate trước chốt. Cutoff đủ tuổi không chứng minh đủ mẫu vật lý.

Late data: lookback hữu hạn 1–2 buckets trên mỗi sync đủ điều kiện + reconcile/rebuild có giới hạn cho thay đổi cũ. Revision/cursor nâng cao phải bao quát correction/delete, không chỉ max observed_at. Không âm thầm bỏ sửa đổi ngoài lookback; có metadata/luồng reconcile hoặc chỉ công bố phạm vi correction được hỗ trợ.

### 9.3. App local-first theo station

- Đổi selectedDeviceIdProvider thành selectedStationIdProvider và repository/notifier family theo station.
- Latest/intraday/daily/config/operation có trạng thái riêng; một request history lỗi không che latest/cache còn dùng được.
- Hiển thị local snapshot trước mạng; refresh giữ content và badge refreshing/stale, không thay toàn dashboard bằng skeleton khi đã có dữ liệu.
- Cache key: station_id + resolution + bucket_start + aggregation_version; daily gồm timezone/calendar date. Dữ liệu source có device/deployment để truy vết, không làm user phải chọn board để xem history trạm.
- Latest cache per station; đối chiếu response identity. Không trả file trạm A khi B offline; file legacy cần migration/clear có kiểm soát.
- Rows và sync metadata commit cùng transaction; missing khác 0; timestamp invalid không dùng now.
- Single-flight theo station/series; request generation/cancel chặn response cũ ghi đè station mới.
- Metadata thời gian tách observed_at, synced_at, last_attempt, connection, freshness và sensor quality. HTTP 200 không chứng minh station online.
- Tải catalogue/name/location từ API, cache offline; không hard-code 3 trạm.
- App không chạy periodic HTTP polling. Live mode là foreground user action với WS lifecycle và TTL, không bật tự động vô hạn khi mở app.

### 9.4. So sánh phương án được chọn

| Phương án | Lợi ích | Giới hạn | Quyết định |
| --- | --- | --- | --- |
| Bỏ gọi kép | Giảm request lặp ngay | Vẫn full scan/history | Làm đầu tiên |
| Chặn theo mốc nhưng vẫn fetch full | Giảm refresh liên tiếp | Mỗi lần được phép vẫn nặng | Chỉ chuyển tiếp |
| Fixed buckets + delta range | Giảm bytes/query/local writes, key ổn định | Cần contract/cursor/coverage | Lõi bắt buộc |
| SQL aggregate | Giảm raw đi qua NestJS | DB còn scan trong range | Triển khai baseline |
| Rollup minute→10m/day | Dùng lại kết quả nhiều client | Cần revision/rebuild | Gate theo tải, dữ liệu nền đã hỗ trợ |
| WS latest + REST delta history | Current mới, history tin cậy | Cần auth/lease/reconcile | Có cho chế độ live được chọn |

## 10. Config, command, alarm và độ bền

### 10.1. Config desired/reported

1. App đọc desired/reported của station và version; gửi patch với expected version.
2. BE kiểm tra quyền, merge đủ 7 trường và validate toàn bộ; resolve active deployment.
3. Trong DB transaction lưu desired version + operation/outbox pending.
4. Worker publish T05 snapshot đầy đủ theo device, có deployment/assignment revision.
5. FW từ chối version cũ/deployment không đúng, dedup cùng version; không write flash nếu không đổi.
6. Storage persist có kiểm tra; áp dụng cấu hình theo thứ tự đã kiểm chứng.
7. Publish T06 reported sau kết quả thật; lỗi có reason. BE không gán reported=desired vì broker PUBACK.
8. App hiển thị pending/applied/failed/unknown và thời gian; reconnect GET reconcile nếu lỡ WS result.

NVS thiết kế snapshot có schema/version/checksum, cân nhắc hai slot/generation. Chỉ cập nhật active snapshot khi ghi/kiểm tra thành công. Mất điện ở giữa phải khôi phục được một version hợp lệ. Không gộp 7 put hiện tại thành khái niệm transaction nguyên tử. Nếu apply RAM/persist có kết quả khác nhau phải report rõ, không log luôn “saved successfully”.

### 10.2. Command và target

BE ledger lưu request ID, actor, station/device/deployment, expected boot khi cần, command/args, created/expiry, status/result. Luồng trạng thái: pending → published → accepted → completed; có failed/expired/unknown. Timeout không chứng minh chưa thực thi; không tự retry operation side-effect với ID mới.

FW queue command tới task sở hữu state, kiểm tra duplicate/expiry, trả kết quả cùng R ở topic và payload. Buzzer duration bị giới hạn; LED set mode/state thay toggle; reboot có contract accepted + boot reconciliation; reset_rain thực hiện ở sensor task và tăng epoch.

Nếu reassign device khi command đang pending, BE phải hủy/expire hoặc xác minh target trước phát; command cũ không được chạy ở station mới. Nếu FW chưa có clock tin cậy, command expiry cần quy tắc an toàn theo loại lệnh; không so sánh epoch bằng thời gian uptime hoặc cho phép mọi lệnh cũ.

### 10.3. Alarm và FCM

Policy ngưỡng thuộc station; reported cho biết firmware đã áp dụng version nào. Backend có thể có policy cloud riêng nhưng phải được đặt tên rõ, không giả khớp local khi dùng global thresholds.

auto_warning điều khiển auto local theo contract hiện tại; buzzer_enabled khác buzzer_test/snooze. Việc push được bật/tắt là policy riêng được expose rõ nếu cần. Sensor invalid/stale không tạo numeric alarm thường; fault alert riêng. Local alarm vẫn chạy offline.

Event/alarm dedup qua restart/multiple instances theo yêu cầu; cooldown trong RAM hiện tại không đủ làm bảo đảm phân tán. Raw/log retry không được nhân bản FCM. Event cũ/backfill phải có chính sách không spam cảnh báo đã qua.

## 11. Kế hoạch FW chi tiết

Mọi task là chưa triển khai. Mỗi task phải có test và measurement liên quan; không thay feature đã đúng bằng bản rewrite không cần thiết.

### FW-PLAN-01 — Build baseline, identity và provision

**Vị trí:** platformio.ini, load_env.py, src/config.h, src/types.h, storage.

- Pin platform/framework/libs theo manifest đã kiểm chứng; SDK đang có là platform 8.0.0, Arduino 3.3.12, IDF 5.5.5.
- Lưu device UUID/provision record/credential reference an toàn; đọc factory MAC đúng API/loại interface; simulator có identity riêng.
- Boot ID mới, stream sequence và config/state versions; không tạo ID mới mỗi reboot.
- Tách namespace dev/staging/prod bằng cấu hình; không in secrets vào log.

**Phụ thuộc:** BE registry/provision contract. **Nghiệm thu:** clean build tái lập; flash/reboot thường giữ ID; factory reset có flow rõ; fake MAC không tự được cấp quyền.

### FW-PLAN-02 — ESP-MQTT transport

**Vị trí:** src/network/mqtt_manager.h/.cpp, taskNetwork.

- Thay implementation trong MqttManager, giữ interface ngoài trong bước transport-only.
- CA/hostname/certificate-time bootstrap; không fallback setInsecure khi lỗi.
- Subscribe T05/T07; publish routes theo bảng; SUBACK readiness, LWT/birth/session.
- Bounded enqueue/outbox, packet max, fragmentation và buffer lifetime.
- Event callback ngắn; queue config/command sang owner task; không write NVS/điều khiển block lâu trong callback.
- Dùng library header đúng SDK pinned; một API có symbol chưa chứng minh runtime đạt.

**Nghiệm thu:** QoS1 ACK được theo dõi; reconnect/fragmented JSON/cert sai/queue đầy có kết quả đúng; min heap/stack/watchdog đo ổn định. Nếu gate không đạt mới đánh giá 256dpi/arduino-mqtt, không đổi cả stack tùy tiện.

### FW-PLAN-03 — Time, sensor quality và counter ownership

**Vị trí:** sensors/sensor_manager.*, main.cpp, types.h, clock service dự kiến.

- Clock sync/quality; monotonic dùng timeout, UTC dùng observation windows.
- Truyền trạng thái DHT hợp lệ, tuổi mẫu và số mẫu; không dùng số 0 thay cho lỗi; tạo event fault/recovery.
- Counter rain nguyên bản + reset epoch; sensor task sở hữu reset, snapshot nhất quán.
- Định nghĩa cửa sổ wind peak rõ; không đổi nhãn thành gust 3 giây nếu chưa có thuật toán tương ứng.
- Sửa snooze elapsed arithmetic wrap-safe.

**Nghiệm thu:** DHT lỗi không tạo low-temp giả; reset song song không race; reboot/reset không âm mưa giả; test rollover và clock unsynchronized.

### FW-PLAN-04 — Minute log và offline buffer

**Vị trí:** accumulator/history_buffer modules dự kiến; sensor/network task.

- Accumulate stats mỗi phút, split partial khi boot/reset/reassign; quality/coverage và identity bất biến khi resend.
- Buffer log tiếp tục nhận khi offline; live chỉ coalesce latest.
- Tham số thử ban đầu: khoảng 30 log phút; cap byte/RAM tổng phải chốt sau đo, không chỉ cap số record.
- ESP outbox và application buffer dùng chung budget có giám sát để tránh nhân đôi RAM không giới hạn.
- Overflow policy được ghi nhận: đếm loss/đánh dấu gap, không âm thầm claim full history. Chế độ mặc định RAM không bảo đảm qua mất điện; persistent telemetry buffer chỉ thêm nếu yêu cầu đó được chọn và kiểm thử wear/power-cut.
- Có rate-limit replay, không bắn toàn backlog làm nghẽn command và event.

**Nghiệm thu:** 30 phút disconnect theo budget thử không tăng heap vô hạn; resend giữ identity/time; reconnect không double-count; payload max không truncate.

### FW-PLAN-05 — Live lease, reported state và events

**Vị trí:** MQTT routing, state/event coordinator, taskAlert.

- Bật live 5s có TTL; không persist NVS, tự hết sau mất BE/app.
- T04 boot/reconnect/changed state; T09 qualified transitions + IDs.
- Local alarm không phụ thuộc subscribe/backend, không spam alarm mỗi 50ms.
- Snooze report giữ alarm active; event hồi phục/counter reset có occurred time/quality.

**Nghiệm thu:** không viewer thì không phát live vô hạn; nhiều viewer chỉ một stream; release/expiry/reboot hoạt động; event đúng transition.

### FW-PLAN-06 — Config persistence và command execution

**Vị trí:** storage/storage_manager.*, main.cpp handlers, command queue/result cache dự kiến.

- Full config snapshot/version/deployment, validate merge/domain; config schema migration không overwrite tùy chỉnh cũ.
- Persist có checksum/generation và check return; chỉ báo persisted/applied theo thực tế.
- Per-request dedup/result, expiry, owner task; chuẩn hóa LED/buzzer/reboot/reset_rain/set_live_mode.
- Quản lý thread safety sysConfig, sensors, hardware; không để hai task cùng ghi state không có ownership.

**Nghiệm thu:** cắt nguồn giữa lúc lưu vẫn khôi phục version hợp lệ; retained replay không ghi flash thừa; command trùng không tạo tác dụng lần hai; xác nhận reboot đúng.

### FW-PLAN-07 — Wi-Fi provisioning và nút vật lý

**Vị trí:** `src/network/wifi_manager.*`, `src/main.cpp`, `src/config.h`, storage/NVS; portal HTTP local dự kiến.

- Lần đầu chưa có credentials hợp lệ: mở AP cấu hình có WPA2 và mật khẩu tạm ngẫu nhiên; hiển thị SSID/AP password và URL local trên OLED. Portal có timeout khi không hoạt động, không phụ thuộc captive-portal auto-detection.
- Sau khi đã setup: khởi động STA bằng credentials NVS. Mất router/mạng chỉ chuyển offline và retry có backoff; không tự mở AP cấu hình chỉ vì lỗi kết nối tạm thời.
- Đổi Wi-Fi chủ động: giữ SET đủ 8 giây, OLED báo/countdown; thả nút sau mốc này mới xác nhận mở portal. Thử credentials mới trước khi thay credentials đang dùng; nếu sai thì giữ credentials cũ và cho thử lại. Khi thử thành công, ghi versioned record an toàn, kiểm tra đọc lại rồi reboot; đóng AP sau khi hoàn tất.
- Tách Wi-Fi credentials khỏi namespace NVS cấu hình cảnh báo; không hard-code SSID/password sản xuất trong `config.h`/firmware và không log credentials. Xem xét NVS/flash encryption theo threat model thiết bị vật lý.
- Nút active-low: GPIO35 UP nhấn ngắn sang trang kế (1→2→3), GPIO34 DOWN nhấn ngắn về trang trước (3→2→1); chặn tại hai đầu trang. SET nhấn ngắn đánh thức màn hình; giữ từ 2 giây đến dưới 8 giây snooze và chỉ thực hiện lúc thả; giữ ít nhất 8 giây rồi thả xác nhận Wi-Fi Setup. OLED phải phân biệt rõ ngưỡng snooze/config để tránh kích hoạt nhầm.
- UP/DOWN hiện chưa được xử lý trong firmware và macro đang tắt. Phần cứng đã được người dùng xác nhận: GPIO35/34 ở mức 1 khi thả, 0 khi nhấn; là input-only, dùng pull-up ngoài và phải để `INPUT`, không dùng `INPUT_PULLUP`.
- Debounce và đo thời lượng dùng phép tính wrap-safe. Việc đọc nút có thể ở task điều khiển hiện hữu, nhưng chỉ `taskNetwork`/WifiManager được thao tác Wi-Fi/AP; gửi yêu cầu qua queue/flag, không chặn task cảm biến/cảnh báo.

**Nghiệm thu:** NVS trống vào portal ở lần đầu; reboot thường reconnect từ NVS mà không phát AP; router down không tự mở portal; tổ hợp nhấn/giữ đúng ngưỡng và không snooze lẫn với provisioning; UP/DOWN đổi đúng trang, không double-trigger; credentials sai không ghi đè credentials tốt; mất điện khi lưu không làm mất record hợp lệ; portal có bảo vệ, timeout và không lộ password trong log.

## 12. Kế hoạch BE chi tiết

### BE-PLAN-01 — Registry, station/deployment và quyền

**Vị trí:** devices module hiện có; stations/deployments/access modules dự kiến; database migrations.

- Audit catalog devices/weather_logs, constraints/index/RLS/grants; không cần khảo sát direct-write EMQX như giả thuyết còn mở.
- Tạo station/device UUID/legacy aliases, deployment transaction, metadata validation và audit.
- Provision/retire credentials, ACL per device; station permissions viewer/operator/admin.
- Phân loại physical/simulator và MAC verified/legacy placeholder; không coi MAC seed là eFuse thật.
- Catalogue paginated; sửa cap<500; GET latest v2 bắt buộc station.

**Nghiệm thu:** replace board giữ history station; reassign không đổi source cũ; quyền chéo bị chặn; legacy ID vẫn resolve đúng trong giai đoạn tương thích.

### BE-PLAN-02 — Router protocol và durable ingestion

**Vị trí:** mqtt/mqtt.service.ts, telemetry module, new DTO/routing/ingestion service.

- Parser T01–T09 + adapter topic cũ có schema explicit; subscription filter cũ +/telemetry không match T01/T02 mới, phải update trước FW rollout.
- Validate payload size/type/ID/quality/time/deployment; counters invalid/conflict.
- Tách live/history, unique log identity, bounded pipeline/ACK boundary.
- Session/consumer lifecycle; tránh hai instance dev/prod cùng ghi; nếu nhiều consumer hợp lệ phải dedup DB.
- Retry/quarantine, persistence failure status và metrics; không fire-and-forget vô hạn.

**Nghiệm thu:** cùng log một row; false DB write không success; live không thành history; replay giữ observed interval; backend offline/reconnect theo session contract.

### BE-PLAN-03 — SQL range, aggregate và daily summary

**Vị trí:** SupabaseService/WeatherService/WeatherController; SQL RPC/migrations.

- Origin cố định cho bucket 10 phút, UTC/ngày theo timezone trạm, khoảng nửa mở và giới hạn range/số điểm.
- Merge minute stats, weighted mean/min/max/rain amount/reset/quality.
- Correction revision, query snapshot/pagination; SQL EXPLAIN + rows/bytes/latency baseline.
- Thêm rollup tăng dần khi cần, rebuild có giới hạn và version; không yêu cầu extension Timescale chưa được xác nhận.
- Legacy raw trước cutoff được chuyển sang semantics có provenance; rain amount unknown/estimated nếu không đủ counter.

**Nghiệm thu:** fixture biên thời gian, nửa đêm và count không đều cho kết quả đúng; cùng nguồn có cùng key; delta 10 phút không đọc lại toàn bộ 7 ngày; missing/correction được thể hiện đúng.

### BE-PLAN-04 — Config/command operations và outbox

**Vị trí:** DevicesService/DTO/controller, new operations/config modules, DB outbox worker.

- Kiểm tra expected version/deployment; validate sau merge, body rỗng, null và args theo từng lệnh.
- Station policy desired, device reported và operation/outbox transaction.
- Publish snapshot retained, retry có cap; command expiry/unknown/reboot semantics.
- Reconcile T06/T08/T04 theo request/version/boot; không đồng nhất published với applied.
- Alias API/command cũ có thời hạn; người gọi biết trạng thái pending thực.

**Nghiệm thu:** phục hồi được sau crash giữa DB/publish; kết quả cũ không hoàn tất operation mới; conflict version rõ; trạng thái unknown không tự retry bằng ID mới.

### BE-PLAN-05 — Current, live sessions và WebSocket

**Vị trí:** websocket gateway, weather latest, new live session coordinator.

- Latest live/log riêng; chỉ update current bằng observation mới hơn hợp lệ; backlog cũ không đè live mới.
- Station rooms/auth, subscribe/revoke/logout; không broadcast mọi trạm tới mọi client.
- Lease foreground watcher, reference counting, TTL/set_live_mode, quota per user/device.
- Availability/state freshness và active deployment mapping; session cũ không offline phiên mới.

**Nghiệm thu:** nhiều viewer dùng một stream; WS không đọc chéo trạm; ngắt kết nối đột ngột vẫn tự hết live; khi không có live, latest dựa trên log 60s và có freshness rõ, không gắn online chỉ vì HTTP 200.

### BE-PLAN-06 — Events, FCM và vận hành

**Vị trí:** NotificationsService, health module, observability/alert policy.

- T09 event ledger/dedup, station policy, quality và stale-event rule.
- FCM token/auth/scope theo sản phẩm; cooldown/restart/multiple consumers không nhân bản notification.
- Hoàn thiện hoặc đánh dấu unavailable forecast/POST telemetry; không giả successstub.
- Liveness/readiness; queue depth, ingest failure/lag, subscriptionstate, operation lag, corrections.
- Retention/rebuild jobs có cap; không lộ raw errors/secrets trong API/log.
- Secret hygiene: quét tracked files, Git history và Docker/build context bằng secret scanner trong CI; không đưa credential vào artifact; có runbook thu hồi/rotate khi phát hiện lộ secret. Không coi `.gitignore` là biện pháp bảo vệ credential đã từng commit.

**Nghiệm thu:** sensor invalid không gây cảnh báo số đo giả; replay cũ không push như sự kiện mới; readiness phản ánh SUBACK/ingest; liveness không tạo vòng restart chỉ vì broker tạm mất kết nối; secret scan không phát hiện credential bị track/đóng gói.

## 13. Kế hoạch App chi tiết

### APP-PLAN-01 — Station catalogue và lựa chọn nguồn

**Vị trí:** api_constants.dart, device_settings_provider.dart, header/settings screens; station model/service/repository dự kiến.

- Tải station catalogue từ BE, cache metadata và quyền; danh sách hard-code không còn là nguồn chính.
- Dùng selectedStationIdProvider; active deployment và hardware diagnostics tách khỏi station selection.
- Dashboard, màn hình chi tiết và Settings dùng cùng station ID; đổi trạm không sửa tên trên số đo cũ.
- Migrate lựa chọn legacy qua alias API; khi logout hoặc đổi tài khoản, cache phải được xóa hoặc scope đúng quyền.
- Tên, vị trí, timezone và trạng thái trạm hiển thị từ metadata; không suy tên từ MAC.

**Nghiệm thu:** A → B, B offline, response A về muộn và quyền B bị thu hồi đều không hiển thị hoặc điều khiển sai nguồn.

### APP-PLAN-02 — Models và storage migration

**Vị trí:** AppDatabase/DAO, WeatherCurrent/Record/DailySummary/Point, LatestWeatherFileStorage.

- Models tách current, rain rate, rain amount, aggregate stats và quality. Không gọi rate là lượng mưa mm.
- Cache theo station/series/resolution/aggregation version/timezone; metadata lưu coverage, revisions, lần thử và lần sync thành công.
- Rows và sync metadata commit trong cùng transaction; latest per station được ghi atomic, không dùng file trạm A cho B.
- Khóa hoặc memoize việc khởi tạo DB đang pending để các tác vụ song song không tự tạo nhiều luồng init.
- Cache legacy có bucket trôi phải được đánh dấu stale/rebuild; không trộn vào key fixed bucket v2.
- Timestamp invalid trả no-data/error rõ; không đổi thành thời gian hiện tại.
- Storage được inject theo platform; Android/iOS và Linux có implementation thực, web chỉ được công bố hỗ trợ sau khi có implementation riêng.

**Nghiệm thu:** migration từ cache cũ không crash; missing khác 0; đổi station/timezone/version không tái sử dụng coverage sai; restart vẫn đọc đúng nguồn.

### APP-PLAN-03 — Incremental sync coordinator

**Vị trí:** AppWeatherRepository, WeatherApiService, dashboard provider; sync service dự kiến.

- Bỏ chuỗi refreshAllData rồi _fetchData gọi mạng lần hai; một lần sync tạo dữ liệu local, UI đọc kết quả từ local/state.
- Bootstrap, range còn thiếu, server cutoff, lookback và reconcile có giới hạn.
- Không request history trong cùng mốc nếu cache đủ và không có correction cần xử lý.
- Single-flight đúng station/series; cancel hoặc generation token loại response cũ; page sau thất bại không advance coverage vượt dữ liệu đã commit.
- Daily summary của sáu ngày trước được cache theo revision; hôm nay partial cập nhật riêng.
- Refresh màn hình chi tiết chỉ yêu cầu resource liên quan, không tải cả tuần vô điều kiện.
- Lỗi và timeout từng resource có fallback riêng; đổi network-first thành local-first.

**Nghiệm thu:** nhiều pull cùng mốc không tải lại history; offline backfill đủ; khoảng không có dữ liệu không query lặp vô hạn; response trạm cũ bị loại.

### APP-PLAN-04 — UI freshness và biểu đồ đúng

**Vị trí:** dashboard state, hero card, intraday/7-day screens, charts/unit/date helpers.

- Hiển thị cache trước, refresh giữ nội dung; latest/day/week có trạng thái loading/error riêng.
- Phân biệt mất mạng điện thoại, device offline, observation stale và sensor fault.
- Current hiển thị rain rate bằng mm/h nếu metric là rate; bucket/day hiển thị amount bằng mm; extrema lấy stats đúng nguồn.
- Ngày theo station timezone; total/partial/unknown có nhãn trung thực.
- Không tạo record nhiệt độ 0 chỉ để lấp chỗ trống và không gán “vừa cập nhật” khi chỉ vừa thử mạng.
- Đo profile build trước tối ưu animation/chart; chỉ animation đang dùng chạy, memoize tính toán khi có bằng chứng cần; giữ RepaintBoundary.

**Nghiệm thu:** không có số 0 hoặc thời gian mới giả; daily summary đúng fixture; một phần API lỗi không che dữ liệu phần khác còn dùng được.

### APP-PLAN-05 — Live foreground và Settings operations

**Vị trí:** DeviceApiService/Repository, config state/Settings; WS/live-session client dự kiến.

- User chủ động start/stop live; join station room, quản lý foreground lifecycle và lease.
- Background, logout hoặc đổi station phải release; không thêm Timer.periodic để polling HTTP.
- Reconnect dùng REST reconcile; nhận WS không thay nguồn lịch sử bền vững.
- Form theo station desired/reported/version; cảnh báo pending hoặc target đã đổi trong lúc edit.
- Operation ID cho command/config, các trạng thái accepted/pending/applied/failed/unknown; GET operation khi cần phục hồi sau mất kết nối.
- Với firmware legacy chưa có ACK thực thi, hiển thị khả năng thực tế thay vì gọi publish thành công là applied.

**Nghiệm thu:** live tự hết TTL; nhiều viewer không tạo nhiều stream; command/config UI phản ánh đúng kết quả và quyền.

### APP-PLAN-06 — Platform và regression

Android/iOS là baseline mobile theo hướng dẫn repository; xác minh riêng các platform đã phát hành. Linux runner cần SQLite FFI runtime/init. Web hiện có giới hạn dart:io/storage, không coi folder web là bằng chứng đã hỗ trợ đầy đủ.

Chạy unit/integration/profile trên môi trường Flutter và máy mục tiêu. Desktop unit test không thay mobile smoke test; sandbox không chạy được Flutter phải được ghi là chưa kiểm chứng, không phải pass.

## 14. Workstream chung: contract, migration, simulator và môi trường

### CROSS-01 — Contract và fixtures

Một nguồn mô tả schema/enums/units/time semantics cho FW/BE/App. Bộ JSON fixtures bao gồm live/log/config/report/command/event, valid/invalid/legacy và failure cases.

Không cần share cùng source binary giữa C++/TypeScript/Dart, nhưng CI phải kiểm tra cùng dữ liệu chuẩn. Phân biệt protocol schema version, aggregation version và config version; tăng một loại không tự tăng hai loại còn lại.

### CROSS-02 — Migration dữ liệu

- Audit read-only và backup trước DDL khi bước implementation được triển khai; kế hoạch hiện tại không apply.
- Additive UUID/alias/deployment và bảng stats. MAC seed không tự trở thành factory MAC đã xác minh.
- Chốt cutover thời gian T theo station/device: legacy raw trước T, log v2 từ T; không cộng cả raw 5s và log phút trong cùng interval như hai nguồn độc lập.
- Không backfill chính xác rain amount từ rate-only khi thông tin đã mất. Giữ unknown hoặc estimation có provenance.
- Legacy temperature có thể tổng hợp lại từ raw với count, nhưng chất lượng DHT chưa được lưu phải là legacy/unknown.
- API cũ có adapter/alias và thời hạn hỗ trợ; source raw/log và aggregation versions có thể truy vết.
- SQLite migration làm invalidation coverage đúng phạm vi; không reset toàn app để né migration và không xóa dữ liệu ngoài scope.

### CROSS-03 — Simulator và test data

Cập nhật tools/simulate_nodes.py để hỗ trợ identity/deployment/boot/sequence, 9 routes, log 60s/live 5s có TTL/events, desired/reported và command response. Simulator có namespace/credentials test riêng, không giả MAC là proof of ownership.

Tạo playback xác định được kết quả: duplicate, out-of-order, clock lỗi, counter reset, offline backlog, payload lớn và fragmented data. Không dùng simulator thử tải hoặc điều khiển production.

### CROSS-04 — Vận hành

Manifest SDK/version pin; BE dùng dependency lock và runtime tương thích. Staging có broker, DB, credentials, quota và board test rõ ràng.

Runbook bao gồm provision/reassign/retire, cấu hình/đổi Wi-Fi bằng nút và portal local, lỗi clock/CA, queue overflow, NVS fail, rebuild history, thu hồi/rotate credential và rollback. CI mock tests có giới hạn; phần hardware/network failure cần môi trường thực riêng.

## 15. Thứ tự triển khai và phụ thuộc

Tất cả phase đều ở trạng thái planned. Chưa đưa lịch ngày hoặc effort như cam kết khi chưa có baseline hardware/staging. Có thể ước lượng sau P0 mà không phải mở lại các quyết định kiến trúc đã chấp thuận.

Trong các bảng rút gọn, FW01 nghĩa là FW-PLAN-01, BE01 nghĩa là BE-PLAN-01 và APP01 nghĩa là APP-PLAN-01.

| Phase | Nội dung chính | FW | BE | App | Gate / phụ thuộc |
| --- | --- | --- | --- | --- | --- |
| P0 | Contract, baseline, audit | FW01 thiết kế | BE01 audit/schema | APP01–02 thiết kế | Fixtures và identity/cadence/topics thống nhất |
| P1 | Correctness và access cấp thiết | FW: hotfix CA + hostname verification; Wi-Fi provisioning/nút vật lý theo FW07 | BE01/04: auth, validation, paging | APP01 và sửa gọi kép/latest identity | Không nhầm trạm/trái quyền; TLS sai phải bị từ chối; commissioning không làm mất credentials tốt; giữ protocol cũ |
| P2 | Transport v2 trên SDK pinned | FW01/02: thay transport sau hotfix; giữ CA verification | Router/ACL staging BE02 | Chưa phụ thuộc | TLS/reconnect/fragmentation/heap đạt; không còn `setInsecure()` |
| P3 | Registry/deployment và receiver | FW03 chuẩn bị identity/quality | BE01/02: schema, dual receiver | APP01 catalogue adapter | Receiver sẵn sàng trước publisher |
| P4 | Publisher log/event/state | FW03/04/05, simulator | BE02/06: processing, cutover | APP02 chuẩn bị models | Identity/time/counter, buffer và ACL đúng |
| P5 | Aggregate/range/daily v2 | Đồng bộ fixtures/counter reset | BE03, migration, query plan | APP02–03: cache/sync | Fixed key, rainfall/stats/coverage đúng |
| P6 | Local-first và UI history | Không chặn | API compatibility/metrics | APP03/04 | Cùng mốc không tải lại; không stale overwrite |
| P7 | Desired/reported, operations và live | FW05/06 | BE04/05/06 | APP05 | ACK/version/NVS/lease end-to-end |
| P8 | Hardening và canary | FW02–06 soak | Toàn bộ failure/observability | APP06 profile/platform | Failure matrix, rollback và runbook |

BE schema cho P7 có thể phát triển song song P5/P6. Không rollout command/config mới trước khi FW hiểu contract. P3/P4 không bắt buộc chờ App v2 nếu adapter legacy đã đạt gate. Rollup nâng cao được tách nếu SQL baseline đã đủ; correctness không phải chờ scale.

### 15.1. Đề xuất chia PR

| PR | Scope | Phụ thuộc | Kiểm chứng |
| --- | --- | --- | --- |
| PR-01 | Contract/fixtures, manifest và audit report | Không | P0 rõ, không DDL live |
| PR-02 | App station identity/latest cache/bỏ gọi kép | PR-01 phần identity | Wrong-station và request-count regression |
| PR-03 | BE auth/validation/paging/stub status | PR-01 | Rights, domain errors, cap 100 |
| PR-03A | FW TLS security hotfix trên MQTT client hiện tại: CA + hostname verification, không fallback `setInsecure()` | PR-01; staging broker/certificate test | Broker hợp lệ kết nối; CA/hostname sai bị từ chối; lệnh/telemetry legacy vẫn hoạt động |
| PR-03B | FW Wi-Fi provisioning và nút vật lý (FW-PLAN-07) | PR-01; xác nhận wiring/pull-up và test trên board | First boot, đổi Wi-Fi, credentials sai/mất điện; button timing/debounce; sensor task không bị block |
| PR-04 | FW toolchain và ESP-MQTT transport; giữ cơ chế xác minh CA/hostname từ PR-03A | PR-01, PR-03A | TLS, reconnect, fragmentation, heap; không mở lại chế độ insecure |
| PR-05 | BE registry/deployment/migrations và aliases | PR-01/03 | Thay board, reassign, gán nguồn dữ liệu đến muộn |
| PR-06 | BE dual-protocol receiver/dedup/bounded ACK | PR-04 contract, PR-05 | Commit failure, replay, live khác log |
| PR-07 | FW quality/clock/counter/accumulator/buffer | PR-04/06 | Log 60s, partial/offline/reset |
| PR-08 | Simulator v2 và cross-layer fixtures | PR-06/07 | Deterministic failure playback |
| PR-09 | BE range SQL/daily/correction API | PR-05/06/07 | Biên, timezone, mưa, query plan |
| PR-10 | App cache migration/incremental sync | PR-02/09 | Bootstrap, gaps, cutoff, atomic cursor |
| PR-11 | App freshness/charts/partial UI | PR-10 | Unit semantics và profile |
| PR-12 | BE config desired/operations/outbox | PR-03/05/06 | Version, crash, retry, operation status |
| PR-13 | FW persist/report/command/availability/events | PR-04/07/12 | NVS, expiry, dedup, rollover |
| PR-14 | BE live lease/WS auth và App live foreground | PR-06/13, APP-PLAN-03 | TTL, viewers, current routing |
| PR-15 | App Settings operations và BE FCM policy | PR-12/13/14 | Pending/applied, stale events, policy |
| PR-16 | Platform/soak/runbook/canary | Các PR liên quan | P8, failure matrix, rollback |

Availability cơ bản và event publisher có thể xuất hiện từ PR-07, được hoàn thiện kết quả/config semantics ở PR-13. Các PR là đơn vị tích hợp có thể điều chỉnh độ lớn, không phải lý do trì hoãn test các phần đã có.

Chưa tạo branch/PR nào. Không gộp các thay đổi formatter hoặc rename repository không liên quan vào các PR này.

## 16. Tiêu chí nghiệm thu theo lớp và đo lường

| Lớp | Gate chức năng | Metric / mục tiêu ban đầu |
| --- | --- | --- |
| FW | Identity bền, log phút, local alarm, live TTL, NVS/command đúng | Min heap/stack, queue bytes/rejects, reconnect/watchdog; ngưỡng sau baseline |
| BE | Deployment/dedup/ACK, live không thành history, range/summary đúng | Received/valid/committed/duplicate/failed, lag, query rows/pages/bytes, p50/p95 |
| App | Đúng trạm, local-first, partial state và incremental sync | Không fetch hai lượt/resource; cùng cutoff đủ coverage có 0 history request |
| Config/command | Desired/reported và kết quả thực | Operation lag, persist fail, timeout/unknown, version conflict |
| Security | Per-device ACL, REST/WS station rights, TLS | Không truy cập chéo; rejection/audit không lộ secret |
| Data | Quality/time/mưa/extrema đúng | Count/coverage/revision, không missing thành 0 |
| UX | Cache trước mạng, live explicit | Mục tiêu warm cache khoảng dưới 200ms theo repo, đo máy đích; chưa là SLA đạt được |
| Runtime | Có baseline/canary và rollback | Không heap suy giảm liên tục/reset ngoài dự kiến trong điều kiện soak đã định |

Tách độ trễ đọc sensor, đóng window, send queue, network, DB commit, aggregate và app display; không gộp tất cả thành “MQTT chậm”. Đo cả log/event/command trong lúc replay backlog, không chỉ lúc Wi-Fi tốt.

Mục tiêu query delta nhỏ không scan full 7 ngày phải kiểm tra query plan/rows, không chỉ số điểm trong response. Animation/chart chỉ tối ưu sau profile; RepaintBoundary không tự bảo đảm 60fps.

## 17. Migration, rollout và rollback chi tiết

1. Lập compatibility matrix protocol v1/v2, HTTP legacy/v2, cache version và NVS schema trước cutover.
2. Backup/audit, additive schema/constraints/index sau kiểm tra dữ liệu; không drop/recreate devices.
3. Deploy BE dual receiver/alias API trước; registry/deployment mapping và metrics legacy/v2 sẵn sàng.
4. Canary một board và simulator staging; pin FW, provision identity, CA/ACL và schema.
5. Chốt thời điểm T theo station; legacy raw trước T, minute log v2 từ T; không dual-write history trùng.
6. App v2 migrate cache/selection; API cũ vẫn được hỗ trợ trong thời gian chuyển; FW cũ không bị gắn nhãn đã ACK thực thi.
7. Mở config/live/command v2 sau gate reporter FW; không gửi retained snapshot schema lạ cho board legacy.
8. So sánh metrics loss/duplicate/quality/alert/heap/request count, rồi rollout từng nhóm.
9. Chỉ bỏ adapter/topic cũ khi không còn client phụ thuộc; xử lý retained cũ bằng danh sách target cụ thể.
10. Rollback App/BE/FW giữ data/schema mới; NVS có fallback hợp lệ, adapter vẫn đọc legacy.
11. Nếu quay về FW v1 gửi raw 5s, reader áp dụng ranh giới nguồn mới rõ ràng; không cộng raw và minute stats chồng nhau.
12. Bàn giao runbook provision/reassign/retire, quyền/ACL, clock error, NVS fail, queue overflow, rebuild history và incident.

Các thông số cần kiểm định còn lại là queue capacity/retention/grace/timeout/hysteresis/calibration và SLA thực đo. Việc kiểm định không mở lại những lựa chọn station/device, 9 topic, log 60/live 5/events và local-first đã đồng ý.

## 18. Traceability: vấn đề → FW / BE / App

Danh mục 36 vấn đề gốc ở phụ lục B được bảo toàn, với bối cảnh source và bằng chứng. Mapping triển khai:

| Nhóm vấn đề | Task chính |
| --- | --- |
| MQ-01, MQ-08 | FW05/06, BE04/05, APP05 |
| MQ-02, MQ-03 | FW01/02/04, BE02, CROSS-03/04 |
| MQ-04, MQ-05, MQ-06 | BE02/03, FW03/04, CROSS-01/02 |
| MQ-07 | FW01/02, BE01/05/06, APP01/05 |
| DT-01, DT-02 | FW03/04, BE02/03, APP02/04 |
| DT-03, DT-04 | FW03/04, BE03, APP02/04 |
| DT-05, DT-06, DT-07 | BE03, APP02/03, CROSS-02 |
| API-01, API-02, API-03 | BE01/04, FW06, APP05 |
| API-04, API-06 | BE01/03, APP01/03 |
| API-05, API-07 | BE06/04, APP04/05, FW05/06 |
| AP-01, AP-02, AP-03 | APP01/02/03, BE01/03 |
| AP-04, AP-05 | APP02/03/04 |
| AP-06, AP-07 | APP02/04/06 |
| FW-01, FW-02, FW-03, FW-04 | FW01–06, BE04, CROSS-01/04 |
| OP-01, OP-02, OP-03 | BE01/02/06, APP06, CROSS-01–04, P8 |
| Wi-Fi provisioning và điều khiển nút vật lý (bổ sung 26/11) | FW07, CROSS-04; kiểm thử P1/P8 |

## 19. Trạng thái ở lần lập kế hoạch này

- Đã tổng hợp khảo sát, xác nhận của người dùng và toàn bộ diễn giải/giải pháp vào một tài liệu.
- Đã chia FW/BE/App, contract/topic/cadence, tests/migration và thứ tự PR.
- Tại thời điểm lập kế hoạch 25/11, chưa triển khai task FW-PLAN, BE-PLAN, APP-PLAN hay CROSS nào.
- Cập nhật review 26/11 bổ sung ưu tiên TLS hotfix trước transport v2, secret-scan/rotation gate, kết quả kiểm thử hiện tại và thiết kế Wi-Fi provisioning/nút vật lý. Người dùng đã xác nhận GPIO35/34 có mức 1 khi thả, 0 khi nhấn; firmware chưa xử lý chúng. Chưa triển khai các thiết kế này hoặc sửa source, toolchain, SQL/migration, broker, Supabase, credentials hay deploy.
- Review nhánh cũ và SQL vận hành cũ là nguồn lịch sử, không tự coi đã apply hoặc khớp model v2. Tài liệu này vẫn là kế hoạch; các phase/PR chưa được triển khai.

## Phụ lục A — Bằng chứng đã kiểm chứng

Các thời điểm trong probe bucket dưới đây là UTC. Ví dụ sync ở mục 9 dùng giờ trạm UTC+7; đây là các ví dụ độc lập.

| Probe/kiểm tra | Kết quả | Giới hạn |
| --- | --- | --- |
| Cùng raw sample lúc `09:58`, history gọi lúc `10:03:12` và `10:07:48` | Bucket lần lượt là `09:53:12` và `09:57:48` | Dùng mock Supabase; đã chạy hàm source thật |
| Handler MQTT.js QoS 1 với listener async hiện tại | `PUBACK → DB_STARTED → DB_COMMITTED` | Mô phỏng handler thật với transport/DB giả lập |
| `saveTelemetry()` trả false | `WS_EMITTED → DB_FAILED → ALERT_CHECKED` | Chưa chứng minh tình huống lỗi DB đã xảy ra trên live |
| Burst 20 telemetry, DB chờ | Có 20 thao tác DB pending đồng thời | Chứng minh không có giới hạn ở lớp code này, không phải benchmark throughput |
| DTO cấu hình `{}` và `{"buzzer":null}` | 0 validation errors | Firmware có thể bỏ qua null; API vẫn chưa báo rõ đây là request không hợp lệ |
| DTO có `temp_min=40`, `temp_max=5`, `humi_max=150`, gió/mưa âm | 0 validation errors | Kiểu dữ liệu hợp lệ nhưng không hợp lệ về domain |
| Mẫu `temp=0`, `humi=0` không có quality | Được DTO nhận; đủ điều kiện LOW_TEMP ở default 10°C | Không có nghĩa 0°C luôn sai; sai ở chỗ không biết trạng thái cảm biến |
| Insert có `timestamp`, `rain_total`, `wind_max` | Các trường này không nằm trong dữ liệu insert hiện tại | Cần đối chiếu schema live trước khi thêm cột |
| Server trả tối đa 100 devices/trang dù còn dữ liệu | `getDevices()` dừng ở 100 dòng, chỉ hỏi offset 0 | Lỗi xảy ra khi server cap thấp hơn 500, không phải kết luận project live đang cap 100 |
| Snooze với `now=4294967040`, thời lượng 300000 ms | Deadline wrap thành 299744; `now < deadline` trả false ngay | Probe số học uint32; chưa chạy dài ngày trên ESP32 |
| SDK cài trên máy | Platform 8.0.0; Arduino-ESP32 3.3.12; IDF 5.5.5; có ESP-MQTT | Có thể khác máy CI hoặc môi trường build mới nếu không pin |


## Phụ lục B — Danh mục 36 vấn đề gốc và hướng xử lý

Ưu tiên **P0**: phải xử lý trước khi cho người không tin cậy truy cập/điều khiển hoặc công bố số đo là đúng. **P1**: tính đúng, mất/trùng dữ liệu và trải nghiệm chính. **P2**: ổn định vận hành, tương thích và tối ưu sau khi có baseline đo. Thứ tự triển khai còn phụ thuộc contract và migration, không chỉ mức ưu tiên.

### B.1. MQTT và ingestion

| ID | Ưu tiên / bằng chứng | Vấn đề và nguy cơ | Giải pháp đề xuất |
| --- | --- | --- | --- |
| MQ-01 | P1 / Source | `adht/weather/status` dùng chung nhưng retained; subscriber mới chỉ nhận retained cuối của một trạm | Availability riêng từng ID; backend wildcard; có boot/session và last-seen |
| MQ-02 | P1 / Source + nguồn chính thức | PubSubClient chỉ publish QoS 0; upstream thông báo ngừng bảo trì | Thử ESP-MQTT; Arduino MQTT là phương án ít thay đổi hơn; chưa cần thay MQTT.js |
| MQ-03 | P1 / Source | Firmware bỏ publish khi disconnected, không backlog; clean session không bảo đảm giữ subscription trong thời gian offline | Phân loại latest/history; buffer giới hạn; quyết định persistent session và chính sách lưu qua reboot |
| MQ-04 | P1 / Probe | PUBACK có trước DB write; write false vẫn bị bỏ qua; crash sau ACK có thể mất mẫu | Chọn một điểm xử lý có backpressure; ACK sau nhận bền vững theo contract; có retry và quan sát failure |
| MQ-05 | P1 / Probe | Mỗi message tạo tác vụ async riêng, chưa giới hạn concurrency; DB chậm làm tăng pending, hoàn tất có thể khác thứ tự nhận | Bounded queue/concurrency; thứ tự theo thiết bị khi cần; timestamp đo không phụ thuộc thứ tự completion |
| MQ-06 | P1 / Source | Chưa có sample ID/dedup; retry hoặc hai backend local/cloud cùng ghi có thể trùng; EMQX không ghi Supabase trực tiếp theo xác nhận người dùng | Unique log identity `(device_id, boot_id, window_sequence)` cho protocol mới; insert idempotent; BE là đường ghi chính, kiểm soát nhiều consumer |
| MQ-07 | P0 / Source, ACL live chưa biết | API chưa có auth; firmware `setInsecure()`; MAC/ID trong payload không chứng minh identity | Authn/authz theo trạm; credentials riêng; broker ACL; xác minh CA/hostname và thời gian TLS; CORS/RLS không thay auth backend |
| MQ-08 | P1 / Source | Broker ACK được app hiểu là đã thực thi; command không request ID/expiry; toggle dễ thực hiện hai lần | Command ledger, ACK thiết bị, timeout/expiry và dedup; ưu tiên lệnh đặt trạng thái; config desired/reported riêng |

Nguồn code: [MQTT backend](../adht-weather-backend/src/modules/mqtt/mqtt.service.ts), [MQTT firmware](../adht-weather-firmware/src/network/mqtt_manager.cpp), [DevicesService](../adht-weather-backend/src/modules/devices/devices.service.ts), [Deploy guide](../adht-weather-backend/DEPLOY_RENDER.md).

### B.2. Ngữ nghĩa và tính đúng của dữ liệu

| ID | Ưu tiên / bằng chứng | Vấn đề và nguy cơ | Giải pháp đề xuất |
| --- | --- | --- | --- |
| DT-01 | P1 / Source + Probe | DTO `timestamp` chưa ánh xạ vào thời gian lưu; firmware không có thời gian đo tuyệt đối | Tách observed/received time; boot/sequence/uptime và clock quality; không gán thời gian nhận cho dữ liệu phát lại |
| DT-02 | P1 / Source + Probe | Không gửi DHT validity/tuổi mẫu; mặc định 0 và giá trị cũ có thể được lưu như mẫu mới; parser lỗi thời gian lại dùng now | Quality theo sensor; null/no-data có nghĩa rõ; reject/quarantine timestamp lỗi; không thay thiếu dữ liệu bằng số 0 |
| DT-03 | P0 / Source | App cộng `rain_rate` mm/h thành `totalRainfall` mm; backend không lưu counter mưa | Lưu counter/tip count và epoch reset; tính lượng mưa tăng thêm; rain rate chỉ là cường độ, tích phân phải xét thời lượng/coverage |
| DT-04 | P1 / Source | Trung bình ngày từ trung bình giờ không có trọng số; min/max lấy từ mean; gust không được lưu | Giữ sum/count/min/max hoặc time-weighted stats; lưu gust đúng nghĩa; không khôi phục extrema từ average |
| DT-05 | P1 / Probe | Bucket có origin bằng `now-range`; mỗi refresh đổi key; SQLite nhận thêm dòng chồng lấn | Origin cố định, interval `[start,end)`; key có resolution và aggregation version; xử lý cache legacy trước delta sync |
| DT-06 | P1 / Source | Ngày biểu đồ theo timezone điện thoại, tài liệu lại kỳ vọng GMT+7; bucket có thể cắt ngang ngày nghiệp vụ | UTC cho lưu trữ; timezone trạm cho ngày/tổng ngày; contract trả timezone; xác định 7 ngày lịch hay rolling 168 giờ |
| DT-07 | P1 / Thiết kế còn thiếu | Chưa phân biệt khoảng đã query, bucket đủ tuổi và độ đầy đủ dữ liệu; thiếu xử lý late arrivals/gaps | Coverage metadata, served-through riêng data watermark; revision hoặc lookback hữu hạn; không advance cursor khi ghi cache chưa xong |

Nguồn: [SupabaseService](../adht-weather-backend/src/modules/database/supabase.service.ts), [telemetry DTO](../adht-weather-backend/src/modules/telemetry/dto/create-telemetry.dto.ts), [repository app](../adht-weather-app/lib/data/repositories/app_weather_repository.dart), [record model](../adht-weather-app/lib/data/models/weather_monitoring_record.dart), [date formatter](../adht-weather-app/lib/core/utils/date_time_formatter.dart).

### B.3. Contract API và cấu hình

| ID | Ưu tiên / bằng chứng | Vấn đề và nguy cơ | Giải pháp đề xuất |
| --- | --- | --- | --- |
| API-01 | P1 / Source | PUT config chỉ publish, không update DB; GET devices chỉ trả ID/name/MAC; form không đọc cấu hình thực | GET config có desired/reported/version; lưu mong muốn và trạng thái delivery; không coi DB là reported khi chưa ACK |
| API-02 | P1 / Probe | Config cho phép body rỗng, null, độ ẩm >100, ngưỡng âm hoặc min>max | Validate patch rồi validate cấu hình sau merge; phân biệt absent/null; reject body rỗng; kiểm tra lại ở firmware |
| API-03 | P1 / Source | Tạo ID cho phép chuỗi MQTT publisher từ chối; command chấp nhận tên bất kỳ, arg chưa theo từng lệnh | Một contract ID dùng chung; enum/schema cho command; registry và quyền thiết bị trước publish |
| API-04 | P1 / Source | Latest cho phép thiếu device ID và lấy mẫu mới nhất toàn bảng | Bắt buộc ID cho endpoint đơn trạm hoặc tách rõ API latest toàn hệ thống; validate response identity ở client |
| API-05 | P1 / Source | POST telemetry báo success dạng stub; forecast trả danh sách rỗng | Hoàn thiện hoặc trả trạng thái unavailable/not implemented rõ; không mô tả stub là xử lý thật; webhook dùng chung ingestion và có auth/dedup |
| API-06 | P2 / Probe | GET devices dừng khi page <500, không xử lý server cap thấp hơn; trả toàn bộ danh mục không có giới hạn client | Đọc tới page rỗng với offset thực hoặc cursor pagination; test cap 100; giới hạn page size và scope quyền |
| API-07 | P1 / Source + snapshot | Ngưỡng FCM global khác cấu hình riêng trạm; auto_warning/buzzer chưa có contract thống nhất; NVS/DB cũ không tự đổi theo default code | Policy cảnh báo theo trạm và fallback rõ; default version; không overwrite giá trị đã tùy chỉnh; định nghĩa riêng local alarm/push |

Nguồn: [controller weather](../adht-weather-backend/src/modules/weather/weather.controller.ts), [WeatherService](../adht-weather-backend/src/modules/weather/weather.service.ts), [TelemetryService](../adht-weather-backend/src/modules/telemetry/telemetry.service.ts), [UpdateConfigDto](../adht-weather-backend/src/modules/devices/dto/update-config.dto.ts), [NotificationsService](../adht-weather-backend/src/modules/notifications/notifications.service.ts).

### B.4. Flutter, cache và hiệu năng

| ID | Ưu tiên / bằng chứng | Vấn đề và nguy cơ | Giải pháp đề xuất |
| --- | --- | --- | --- |
| AP-01 | P1 / Source | Refresh gọi `refreshAllData()` rồi `_fetchData()`, tải latest/24h/7d hai lượt; màn hình chi tiết refresh cả bộ | Một coordinator đồng bộ; fetch một lần rồi đọc cache/state; scope theo phần cần refresh |
| AP-02 | P0 / Source | Dropdown dashboard đổi tên nhưng không đổi selected ID; còn ưu tiên `prev.current`; Settings đổi ID nhưng notifier chỉ `ref.read` repo | State/repository theo ID; request/result gắn ID; không đổi nhãn trên số đo cũ; config form cũng tách theo trạm |
| AP-03 | P1 / Source | File latest dùng chung; fallback chưa check ID; có thể trả mẫu trạm A khi đang chọn B | Latest cache keyed theo thiết bị; kiểm tra identity và migration file cũ; lưu atomic để tránh ghi chồng/hỏng file |
| AP-04 | P1 / Source | Network-first dù có cache; Future.wait gộp lỗi; loading thay nội dung cũ; online=true khi REST trả dữ liệu cũ; lastUpdated=now | Local-first; trạng thái riêng latest/day/week; stale-while-refresh; tách observed/synced/attempt time và connectivity/freshness |
| AP-05 | P1 / Source | Chưa single-flight và chặn response cũ; không có sync metadata theo ID/resolution; cache bucket cũ không thích hợp delta | In-flight dedup, request generation/cancel; cursor/coverage và rows commit cùng transaction; version hóa cache |
| AP-06 | P2 / Source | Linux runner chưa khởi tạo SQLite FFI runtime; web dùng dart:io/path và SQLite cần implementation riêng | Xác định platform hỗ trợ; DI database/file storage theo platform; Linux smoke test; chưa cam kết web hoạt động |
| AP-07 | P2 / Source, chưa profile | Cả rain/sun animation chạy; chart map/sort trong build; RepaintBoundary đã có nên chưa chứng minh chart là bottleneck | Đo profile build trên máy thật; pause animation không hiển thị; memoize khi cần; ưu tiên network/DB trước |

Nguồn: [dashboard provider](../adht-weather-app/lib/providers/weather_dashboard_provider.dart), [latest storage](../adht-weather-app/lib/data/storage/latest_weather_file_storage.dart), [AppDatabase](../adht-weather-app/lib/data/database/app_database.dart), [settings](../adht-weather-app/lib/views/screens/settings_screen.dart), [hero card](../adht-weather-app/lib/views/widgets/current/hero_weather_card.dart), [chart](../adht-weather-app/lib/views/widgets/charts/intra_day_spline_chart.dart).

### B.5. Firmware và vận hành

| ID | Ưu tiên / bằng chứng | Vấn đề và nguy cơ | Giải pháp đề xuất |
| --- | --- | --- | --- |
| FW-01 | P1 / Source + SDK | RAM cập nhật trước, NVS ghi 7 key riêng và không kiểm tra return; log luôn báo thành công | Snapshot cấu hình có schema/version/checksum, cân nhắc hai slot; kiểm tra persist; ACK sau kết quả đúng; dedup để tránh ghi thừa |
| FW-02 | P1 / Source, chưa tái hiện hardware | Core 0 reset mưa trong lúc Core 1 cập nhật; một số biến thời gian/rate không có cùng cơ chế khóa | Sensor task sở hữu state; nhận yêu cầu reset qua queue; reset counter epoch và xuất snapshot nhất quán |
| FW-03 | P2 / Probe số học | `now < alarmSnoozedUntilMs` sai khi millis uint32 wrap khoảng 49,7 ngày | Elapsed time unsigned với active flag; test ngay trước/sau wrap và snooze đã hết |
| FW-04 | P1 / SDK + Source | Platform không pin; đổi MQTT làm callback/task model khác; SDK cài chưa là cam kết CI | Pin platform/framework/libs, lưu manifest; spike ESP-MQTT; bounded queues và xử lý fragmentation; đo heap/watchdog |
| OP-01 | P1 / Snapshot, cần catalog live | Chưa có baseline schema đầy đủ được quản lý; unique MAC/RLS/grants chưa xác nhận trực tiếp qua catalog | Chạy audit read-only; migration additive; bảng devices đang có dữ liệu, không tạo/drop lại; SQL riêng không sửa lỗi auth backend |
| OP-02 | P2 / Source | Health 200 chỉ chứng minh liveness; connected có trước SUBACK; WS broadcast mọi client, thiếu theo dõi last ingest/DB errors | Liveness/readiness riêng; auth và rooms theo quyền; metrics ingest, queue, persistence, freshness; giữ health nhẹ |
| OP-03 | P1 / Kiểm tra trước | Test mock chưa bao phủ failure end-to-end; forecast test/mock có mismatch; Socket.IO bị sandbox chặn; Linux/hardware chưa xác minh | Thiết lập baseline test đúng môi trường, bộ failure tests và kiểm thử board thật; không coi mọi failure là regression mới |

**Bổ sung từ review 26/11/2026:** backend build pass nhưng `node --test test/*.test.cjs` chỉ pass 32/36; cả 4 failure nằm ở `weather-forecast.test.cjs`. `WeatherService.getForecast()` hiện còn stub và trả `forecast_days: []`; test double cũng thiếu `logger.log()`, nên cần sửa cả implementation lẫn mock trước khi xem suite là xanh. Đây là bằng chứng hiện tại, thay cho ghi chú cũ chỉ nêu logger mock. Flutter `analyze` và `test` pass; firmware `pio run` pass. Các kiểm tra này không thay integration test, Supabase/staging hay kiểm thử board thật.

Nguồn: [main firmware](../adht-weather-firmware/src/main.cpp), [sensor manager](../adht-weather-firmware/src/sensors/sensor_manager.cpp), [storage manager](../adht-weather-firmware/src/storage/storage_manager.cpp), [platformio.ini](../adht-weather-firmware/platformio.ini), [health](../adht-weather-backend/src/modules/health/health.controller.ts), [WebSocket](../adht-weather-backend/src/modules/websocket/telemetry.gateway.ts).


## Phụ lục C — Ma trận kiểm thử chi tiết

| Nhóm | Case bắt buộc | Kết quả mong đợi |
| --- | --- | --- |
| Trạm | A→B, B offline, request A về muộn, Settings đổi ID | Không đổi nhãn trên dữ liệu A; B không fallback file A |
| Refresh | Nhiều pull trước cùng cutoff, hai màn hình refresh | Không gọi bộ API hai lần; single-flight đúng key |
| Bootstrap | Cache rỗng giữa bucket, cache bị evict, app reinstall | Tải đủ phạm vi ban đầu; không skip vì lastAttempt còn mới |
| Incremental | Miss 2 giờ, offline nhiều ngày, paginated response | Backfill đủ trong retention; cursor chỉ commit cùng dữ liệu |
| Gaps | Một bucket/day không có mẫu, sensor lỗi, trạm offline | Hiển thị missing/partial; không dùng 0 để giả có dữ liệu |
| Bucket | Cùng sample gọi lúc khác nhau, mẫu đúng biên, midnight | Khóa ổn định; mỗi mẫu thuộc một bucket; ngày đúng timezone trạm |
| Correction | Late sample, sửa bucket cũ, đổi aggregation version | Update bằng revision/lookback/rebuild; không append bucket chồng lấn |
| Summary | Count giờ khác nhau, extrema trong giờ, today partial | Avg có trọng số theo contract, extrema không lấy từ mean, coverage rõ |
| Rain | Counter tăng, trùng mẫu, reset trong boot, reboot, khoảng thiếu | Không double count/âm giả; đánh dấu thiếu hoặc ước lượng khi không thể phân bổ |
| Quality | DHT chưa từng valid, lỗi >timeout, hồi phục | Không gửi cảnh báo low-temp từ sentinel 0; giữ sensor khỏe khác |
| Timestamp | Không đồng bộ, timestamp lỗi, mẫu phát lại | Không thay thời gian lỗi bằng now; giữ observed time hoặc quality ước lượng |
| Dedup | Same identity/payload, same identity khác payload, 2 consumer | Một raw row/side effect; conflict payload được ghi nhận |
| ACK | DB chậm/fail, crash sau nhận/trước commit, sau commit/trước ACK | Retry/idempotence đúng; không báo persist sai; queue có giới hạn |
| MQTT offline | Wi-Fi/broker/backend ngắt, session expiry, broker restart | Hành vi backlog/loss theo contract; reconnect không lặp lệnh nguy hiểm |
| MQTT parser | Payload >buffer, fragmented event, JSON lỗi | Ghép đủ hoặc từ chối có giới hạn; không parse chunk thành JSON hoàn chỉnh |
| TLS/ACL | CA sai, hostname sai, clock chưa đủ tin cậy, A publish topic B | Từ chối phù hợp; không fallback insecure; không truy cập chéo trạm |
| Config | Null/rỗng/ngưỡng sai, partial merge, concurrent versions | Reject đúng; giữ trường không gửi; version conflict rõ |
| Persist config | NVS write fail, mất điện giữa lưu, nhận lại retained | Recover một version hợp lệ; không ACK persisted sai; không ghi flash thừa |
| Command | Trùng request ID, quá hạn, toggle, reboot trước/sau response | Không thực thi lại; status unknown/accepted/applied đúng contract |
| Availability | Nhiều trạm, retained replay, LWT cũ sau reconnect | Snapshot riêng từng ID; không offline phiên mới do event cũ |
| Firmware runtime | Reset rain cùng sensor update, millis wrap, queue đầy | State nhất quán; snooze đúng; watchdog/heap trong ngưỡng |
| Wi-Fi provisioning | NVS trống, router down, nhập SSID/password sai/đúng, đổi mạng, portal timeout, mất điện khi ghi | AP chỉ mở đúng lúc; không mất credentials cũ; reconnect/recovery và thông báo OLED đúng |
| Nút vật lý | GPIO34/35 active-low, bounce, SET duration 2s ≤ t < 8s và t ≥ 8s, nhấn UP/DOWN ở trang 1/3 | Không double-trigger; snooze và provisioning tách biệt; điều hướng đúng; không block task mạng/cảm biến |
| API | Thiếu ID, ID không hợp lệ, cmd lạ, cap thấp, webhook/forecast | Không trả nhầm trạm; domain errors rõ; không giả success stub |
| Alert | Retry duplicate, trạm đổi ngưỡng, sensor invalid, restart/2 process | Ngưỡng/policy đúng; side effect không nhân bản theo khả năng đã cam kết |
| Platforms | Android/iOS đã cam kết, Linux FFI, web nếu được chốt hỗ trợ | Storage đúng implementation; không coi desktop unit test là mobile smoke test |
| Hiệu năng | Cold/warm start, cache refresh, history query, soak/animation | Thu metric thật theo mục 16; không quy kết chart/network chỉ từ cảm giác |
| Station/deployment | Thay board, điều chuyển, log cũ đến sau khi reassign | Giữ lịch sử station đúng nguồn; target command cũ không chạy ở station mới |
| Topic ACL | D publish T05/T07 hoặc topic của thiết bị khác | Broker từ chối; BE không tin payload identity tự khai |
| Live/log | Live mỗi 5s đồng thời log phút và nhiều viewers | Chỉ log vào history; một stream/device; last viewer rời hoặc TTL hết thì dừng |
| Log boundary | Boot/reset/reassign giữa phút, clock sync sau boot | Partial interval/provenance đúng, không trộn epoch/deployment |
| Lease lifecycle | App crash/background/logout, BE restart hoặc stop thất lạc | FW tự hết TTL; không giữ live persistent trong NVS |
| Simulator | Node ảo không có factory MAC và giả mạo ID physical | Provision/ACL riêng; metadata không coi MAC giả là phần cứng thật |
| Legacy cutover | Raw 5s trước T và minute v2 sau T, rollback về FW cũ | Không double count; cache/API nhận đúng source/aggregation version |
| Clock/TLS | SNTP chưa xong, giờ sai hoặc certificate validation thất bại | Không tắt CA verification để vượt lỗi; clock quality và retry an toàn |

Không yêu cầu thêm test chỉ phản chiếu implementation. Các case trên kiểm tra contract, failure boundary và nguy cơ đã xác định. Unit/probe trước không thay integration/hardware tests; lỗi môi trường test phải được tách khỏi lỗi sản phẩm.


## Phụ lục D — Nguồn tham khảo và tài liệu liên quan

- [PubSubClient upstream](https://github.com/knolleary/pubsubclient): giới hạn publish QoS 0 và thông báo tình trạng bảo trì tại lúc khảo sát; không suy từ đó rằng mọi firmware đang chạy đều gặp lỗi.
- [ESP-MQTT](https://docs.espressif.com/projects/esp-mqtt/en/latest/esp32/): QoS, outbox/enqueue, events và fragmented data. Tài liệu latest có thể khác SDK local 5.5.5; implementation phải theo header/version đã pin.
- [256dpi/arduino-mqtt](https://github.com/256dpi/arduino-mqtt): publish QoS và lưu ý gọi API trong callback.
- [AsyncMqttClient](https://github.com/marvinroger/async-mqtt-client): khả năng async/QoS/TLS đã khảo sát; chưa xác nhận phù hợp toolchain dự án.
- [MQTT.js API](https://github.com/mqttjs/MQTT.js#api): handleMessage/backpressure và store; probe cũng đọc handler của phiên bản cài trong backend.
- [MQTT 3.1.1, OASIS](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html): retained theo topic và semantics QoS; không bảo đảm transaction database/side effect ứng dụng.
- [AWS Device Shadow](https://docs.aws.amazon.com/iot/latest/developerguide/device-shadow-data-flow.html): mô hình desired/reported/delta và đồng bộ trạng thái.
- [ThingsBoard RPC](https://thingsboard.io/docs/reference/mqtt-api/rpc/) và [Attributes](https://thingsboard.io/docs/reference/mqtt-api/attributes/): tách lệnh request/response và cấu hình.
- [PostgreSQL date_bin](https://www.postgresql.org/docs/16/functions-datetime.html#FUNCTIONS-DATETIME-BIN): fixed interval và origin.
- [Timescale/Tiger Data aggregates](https://www.tigerdata.com/docs/learn/continuous-aggregates): mô hình rollup tăng dần; không mặc định project Supabase có hỗ trợ extension.
- [Flutter offline-first](https://docs.flutter.dev/app-architecture/design-patterns/offline-first): repository hợp nhất local/remote, trả local trước rồi đồng bộ.
- [ESP-TLS](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/protocols/esp_tls.html): xác minh server bằng CA/certificate bundle; dùng tài liệu đúng SDK khi triển khai.

- [OGC SensorThings](https://docs.ogc.org/is/15-078r6/15-078r6.html): phân tách Thing/Location/HistoricalLocation/Sensor/Observation; tham khảo cách quản lý vị trí/lịch sử, không ép triển khai toàn chuẩn.
- [WMO WIGOS station identifier FAQ](https://community.wmo.int/site/knowledge-hub/programmes-and-initiatives/wmo-integrated-global-observing-system-wigos/implementation-of-wmo-integrated-global-observing-system-wigos/frequently-asked-questions-faqs-wigos-station-identifier-wsi): đánh giá tính liên tục khi thay đổi vị trí trạm.
- [Espressif MAC APIs](https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/system/misc_system_api.html#mac-address): base MAC, interface MAC và khả năng tùy chỉnh.
- [AWS topic design](https://docs.aws.amazon.com/pdfs/whitepapers/latest/designing-mqtt-topics-aws-iot-core/designing-mqtt-topics-aws-iot-core.pdf): định danh/định tuyến trong topic và phân tách data/command.
- [ThingsBoard MQTT identity/topic](https://thingsboard.io/docs/reference/mqtt-api/getting-connected/): topic chung me dựa trên identity credentials của nền tảng.
- [Home Assistant MQTT](https://www.home-assistant.io/integrations/mqtt/): state, command, availability và birth/LWT.
- [ESPHome sensor filters](https://esphome.io/components/sensor/): tổng hợp theo thời gian, thay đổi và heartbeat.
- [WMO OSCAR wind gust](https://space.oscar.wmo.int/variables/view/wind_gust): định nghĩa cực đại của trung bình trượt 3 giây; peak mẫu 5s hiện tại không tự tương đương.
- [Review nhánh cũ](DEVICE_API_REVIEW.md): nguồn lịch sử; đọc đính chính baseline ở mục 1 trước khi áp dụng.
- [SQL devices đã soạn riêng](SUPABASE_DEVICES_SQL.md): không phải toàn bộ migrations station/deployment/history v2, không được tự coi đã apply.

Các vị trí code đã liên kết trong mục 5 thuộc baseline ghi ở mục 1; khi code thay đổi cần review lại kết luận. Tài liệu ghi giải pháp đã được đồng ý và kế hoạch chi tiết; không xác nhận các task đã được triển khai hoặc hệ thống đã đạt tiêu chí production.
