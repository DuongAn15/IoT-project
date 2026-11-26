# P07 — Live, WebSocket và alerts

**Trạng thái:** Planned
**Mục tiêu:** live/current không bị nhầm với history/availability; quyền theo station; cảnh báo chỉ phát theo policy và transition.

## Phạm vi

- Firmware availability per device, reported state và event transitions có sequence/ID/quality; local alarm vẫn chạy offline.
- Backend latest/live/history tách riêng; update current chỉ khi sample hợp lệ mới hơn; status/event dedup.
- WebSocket auth, station rooms, subscribe/unsubscribe/revoke/logout; không broadcast toàn bộ trạm tới mọi client.
- Live lease TTL có reference counting; app chỉ dùng foreground session, release khi đổi station/background/logout.
- Alarm policy theo station; tách local buzzer, FCM policy và sensor fault/stale; FCM chống duplicate qua retry/restart/multiple instance.

## Ngoài phạm vi

Không persist mọi live sample thành history; không dùng HTTP 200 hoặc retained status cũ để tự kết luận thiết bị online; không thêm polling loop liên tục.

## Phụ thuộc và thứ tự

P01 auth, P03 station/device binding, P04 state/event receiver. Firmware event/state có thể đi cùng P06 nhưng schema phải tách khỏi operation ACK.

## Nghiệm thu

- User không đọc/subscribe chéo station; revoke/logout đóng room/lease.
- Một device có nhiều viewer nhưng một live stream; TTL dọn session mất kết nối.
- Status cũ/LWT cũ không đánh offline session mới; stale sensor không tạo numeric alert giả.
- Replay/event duplicate không tạo push trùng theo policy.
- Không có viewer thì live chấm dứt; history chỉ nhận log theo cadence.

## Rollout/rollback

Bật WS rooms/lease theo feature flag và một station canary; giữ REST latest fallback. Tắt live không ảnh hưởng local alarm hay history.

**Tham chiếu:** `FW-PLAN-05`, `BE-PLAN-05/06`, `APP-PLAN-05`; MQ-01/08, API-07, OP-02.
