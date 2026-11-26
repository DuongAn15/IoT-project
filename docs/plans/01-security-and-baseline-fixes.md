# P01 — Security và lỗi cần chặn trước production

**Trạng thái:** Planned
**Mục tiêu:** đóng các đường điều khiển/truy cập không xác thực và không báo thành công sai, đồng thời giữ protocol hiện hữu.

## Phạm vi

1. Thêm authentication/authorization cho REST quản lý, đọc và điều khiển thiết bị; giới hạn quyền theo role/device. Bảo vệ WebSocket và FCM registration theo policy. CORS/RLS không thay auth backend.
2. Kiểm tra command enum/args, device ID và config sau khi merge; reject body rỗng/null, domain values sai.
3. Hotfix firmware TLS trên MQTT client hiện tại: xác minh CA và hostname; không có fallback `setInsecure()`.
4. Forecast và HTTP telemetry stub phải trả unavailable/not-implemented rõ, hoặc hoàn thiện qua pipeline có auth/dedup; không giả success.
5. Secret scanning cho Git/history/build context, CI và quy trình thu hồi/rotate credentials.

## Ngoài phạm vi

Không thay MQTT library/protocol v2, không thiết kế full station/deployment registry, không chạy migration production.

## Phụ thuộc và thứ tự

P00 trước. Backend auth, firmware TLS và test secrets có thể triển khai song song ở PR tách biệt. Giữ adapter legacy đến khi client migration hoàn tất.

## Nghiệm thu

- Request chưa auth bị từ chối; quyền chéo thiết bị/trạm bị chặn; WS không subscribe chéo.
- Input sai bị reject với lỗi domain ổn định; không tạo/publish lệnh sai.
- Broker thật/staging được xác minh CA/hostname; cert sai thất bại; không có insecure fallback.
- API stub không trả `success` giả; tests forecast/webhook khớp hành vi đã chốt.
- Secret scan không phát hiện credential bị track/đóng gói; log không chứa secret.

## Rollout/rollback

Deploy backend auth tương thích theo adapter/token plan trước khi ép client cũ. Firmware TLS hotfix canary một board; nếu chứng chỉ/clock chưa sẵn sàng thì dừng rollout, không tắt xác minh TLS. Rollback không được mở lại endpoint điều khiển public hoặc `setInsecure()`.

**Tham chiếu:** kiến trúc mục 8.4, BE-PLAN-06, FW-PLAN-02; vấn đề MQ-07, API-02/03/05, OP-03.
