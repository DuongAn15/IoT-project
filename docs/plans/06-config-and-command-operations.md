# P06 — Config và command operations

**Trạng thái:** In Progress
**Mục tiêu:** phân biệt desired, published, accepted, persisted, applied và kết quả thực thi xuyên BE–FW–App.

## Phạm vi và thứ tự

1. **Backend:** station desired config/version; validate sau merge; operation ledger + outbox trong transaction; expiry, idempotency, quyền actor/target.
2. **Firmware:** nhận snapshot/version, queue tới owner task, validate, persist có version/checksum và kiểm tra lỗi; command dedup/expiry; ACK result theo request/deployment/boot.
3. **App:** đọc desired/reported/version; gửi operation; hiển thị pending/applied/failed/unknown; GET reconcile khi WS/HTTP bị ngắt.

Command side effects (reboot, buzzer, reset rain) và config snapshot có semantics khác; không dùng chung retry/retain mặc định.

## Ngoài phạm vi

Không báo “đã lưu” theo PUBACK; không tự retry side-effect bằng request ID mới; không publish v2 tới firmware chưa hỗ trợ.

## Phụ thuộc và thứ tự

P01 validation/auth, P03 registry/deployment và P04 device identity/routes. Có thể làm schema/backend contract và FW spike song song; end-to-end test/rollout chỉ sau khi cả ba lớp sẵn.

## Nghiệm thu

- Concurrent version conflict rõ; partial merge giữ nguyên field không gửi; null/empty/domain-invalid bị reject.
- DB commit/publish crash/retry không tạo operation trùng.
- Firmware NVS fail không ACK persisted/applied; power-cut khôi phục version hợp lệ.
- ACK request cũ/boot/deployment khác không hoàn tất operation mới.
- App phân biệt broker receipt với device result và khôi phục trạng thái sau mất kết nối.

## Rollout/rollback

Adapter API cũ trả `sent/pending` trung thực trong giai đoạn chuyển. Mở config/command v2 theo canary; ngừng publish nếu firmware version không tương thích.

**Tham chiếu:** `BE-PLAN-04`, `FW-PLAN-06`, `APP-PLAN-05`; MQ-08, API-01/02/03.
