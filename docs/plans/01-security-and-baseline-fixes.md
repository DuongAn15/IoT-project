# P01 — Security và lỗi cần chặn trước production

**Trạng thái:** Implemented on branch `feat/p01-security-hardening` — Supabase ACL/anon denial, backend API/WS auth, strict DTO/command/config validation, firmware TLS CA/hostname verification, forecast deferral, và CI secret scan workflow đã hoàn tất; secret rotation trên live thuộc vận hành.
**Mục tiêu:** đóng các đường điều khiển/truy cập không xác thực và không báo thành công sai, đồng thời giữ protocol hiện hữu.

**Finding P00 cần xử lý:** catalog audit và follow-up read-only ghi nhận `weather_logs` có policy role `{public}` cho SELECT (`qual=true`) và INSERT (`with_check=true`), cùng table grants rộng cho `anon`/`authenticated`. Column grants xác nhận hai role này có INSERT/REFERENCES/SELECT/UPDATE trên mọi cột của cả `devices` và `weather_logs`, bao gồm cột identity `weather_logs.id`. Người dùng xác nhận project đang lưu dữ liệu thật, nên xem đây là finding đang áp dụng trên môi trường live (không phải staging cô lập), dù dữ liệu có thể bỏ. Nếu project được expose qua PostgREST, đây là đường đọc history/chèn dữ liệu chưa được giới hạn. Project ref `umsysvgxprlwpqmblwie` và SQL Editor role `superuser` đã được người dùng cung cấp. Không có policy/grant nào được thay đổi trong P00; xóa rows không khắc phục quyền truy cập.

**Kiểm tra consumer và trạng thái thay đổi:** backend config ưu tiên `SUPABASE_SERVICE_ROLE_KEY`; người dùng xác nhận biến này có giá trị trong backend đang chạy. Không tìm thấy Supabase client/REST call trong `adht-weather-app/lib` hoặc `adht-weather-firmware/src`; người dùng xác nhận không có client hay ứng dụng nào truy cập trực tiếp Supabase. Người dùng báo đã chạy [`p01-supabase-access-hardening-draft.sql`](../p01-supabase-access-hardening-draft.sql) thành công trên project live. Post-check read-only cho thấy RLS vẫn bật, policy query không trả rows, table/column grants không còn cho `anon`/`authenticated` và `service_role` vẫn giữ grants. Đây là xác nhận ACL ở catalog. Ảnh người dùng gửi cho thấy `weather_logs` tiếp tục nhận các bản ghi bình thường cách nhau khoảng 5 giây sau hardening, xác nhận đường ghi telemetry vẫn hoạt động. Người dùng xác nhận app hoạt động bình thường sau hardening, bổ sung bằng chứng cho đường đọc backend. GET anon sau hardening tới `/rest/v1/weather_logs?select=id&limit=1` trả HTTP `401`, mã `42501` (`permission denied for table weather_logs`); key và row ID không được in/lưu. Dùng [`p01-supabase-access-hardening-postcheck.sql`](../p01-supabase-access-hardening-postcheck.sql) để tái lập.

## Phạm vi

1. Thêm authentication/authorization cho REST quản lý, đọc và điều khiển thiết bị; giới hạn quyền theo role/device. Bảo vệ WebSocket và FCM registration theo policy. CORS/RLS không thay auth backend.
2. Khóa đường Supabase trực tiếp ngoài ý muốn: xác nhận project/environment và mọi consumer trước; rà lại policy/grants cho `weather_logs` và `devices`; loại bỏ quyền/policy `public` hoặc `anon` không cần thiết, chỉ giữ quyền tối thiểu theo access model đã duyệt. Audit thấy grants rộng gồm `TRUNCATE`; RLS không giới hạn quyền này nên phải rà riêng. REST resource API chuẩn không cung cấp arbitrary SQL, vì vậy không suy ra truncate qua PostgREST nếu chưa có đường gọi SQL phù hợp. Backend dùng service-role key phải giữ ở server; không đưa key này vào app/firmware. Không áp dụng remediation trước khi xác nhận target và phụ thuộc.
3. Kiểm tra command enum/args, device ID và config sau khi merge; reject body rỗng/null, domain values sai.
4. Hotfix firmware TLS trên MQTT client hiện tại: xác minh CA và hostname; không có fallback `setInsecure()`.
5. Forecast tạm hoãn để phát triển sau: giữ source/spec, comment out route/service/config và skip forecast tests trong lúc feature chưa được duyệt lại. HTTP telemetry stub phải trả unavailable/not-implemented rõ hoặc chỉ mở qua pipeline có auth/dedup.
6. Secret scanning cho Git/history/build context, CI và quy trình thu hồi/rotate credentials.

## Ngoài phạm vi

Không thay MQTT library/protocol v2, không thiết kế full station/deployment registry. P00 không chạy migration; P01 chỉ author/review và triển khai thay đổi DB theo release gate sau khi xác nhận target, consumer, staging test và rollback.

## Phụ thuộc và thứ tự

P00 trước. Phần hardening DB bị chặn cho tới khi xác nhận project/environment và rà soát consumer trực tiếp; sau đó staging migration/negative tests trước production. Backend auth, firmware TLS và test secrets có thể triển khai song song ở PR tách biệt. Giữ adapter legacy đến khi client migration hoàn tất.

## Nghiệm thu

- Request chưa auth bị từ chối; quyền chéo thiết bị/trạm bị chặn; WS không subscribe chéo.
- Trên đúng môi trường đã xác nhận, role `anon` không còn đọc/ghi trực tiếp các bảng nhạy cảm; API backend hợp lệ vẫn hoạt động. Có kiểm thử positive/negative qua PostgREST và migration/rollback được review. Quyền `authenticated` chỉ còn nếu có consumer và policy cụ thể được duyệt.
- Input sai bị reject với lỗi domain ổn định; không tạo/publish lệnh sai.
- Broker thật/staging được xác minh CA/hostname; cert sai thất bại; không có insecure fallback.
- API stub không trả `success` giả; forecast không được expose khi đang hoãn. Forecast code/spec được giữ lại nhưng route/config bị comment out và tests skip; chỉ bật lại theo plan/contract được duyệt.
- Secret scan không phát hiện credential bị track/đóng gói; log không chứa secret.

## Rollout/rollback

Deploy backend auth tương thích theo adapter/token plan trước khi ép client cũ. DB permission migration phải chạy staging trước, có snapshot/rollback đã review và kiểm thử lại; không rollback bằng cách mở lại public `SELECT`/`INSERT`. Firmware TLS hotfix canary một board; nếu chứng chỉ/clock chưa sẵn sàng thì dừng rollout, không tắt xác minh TLS. Rollback không được mở lại endpoint điều khiển public hoặc `setInsecure()`.}

**Tham chiếu:** kiến trúc mục 8.4, BE-PLAN-06, FW-PLAN-02; vấn đề MQ-07, API-02/03/05, OP-01, OP-03; bằng chứng P00 tại [`p00-staging-audit-template.md`](../p00-staging-audit-template.md).
