# P04 — MQTT telemetry pipeline v2

**Trạng thái:** Backend v2 persistence (`weather_logs_v2`), union history/latest, `V2_CUTOVER_ENABLED`, và production `DEVICE_DEPLOYMENTS` binding đã triển khai; firmware accumulator đã có và publisher còn gated (`ENABLE_V2_MINUTE_LOG_PUBLISHER=0`, `PubSubClient` QoS 0 + RAM backlog 12 slot). Production sign-off chờ canary/QoS/hardware tests.
**Mục tiêu:** lịch sử log idempotent, live/state/event tách semantics; backend sẵn sàng trước khi firmware phát v2.

## Phạm vi và các chặng

1. **Transport:** pin SDK, thử ESP-MQTT trên board, CA/hostname từ P01, reconnect/QoS/fragmentation/heap; giữ topic/payload legacy trong PR transport-only.
2. **Backend receiver:** dual receiver v1/v2, validate type/ID/deployment/time/quality/size; dedup key; bounded processing; persistence/error/ACK semantics; không ghi DB trực tiếp từ EMQX.
3. **Test producer:** simulator v2 với identity riêng và deterministic duplicate/out-of-order/offline/oversized cases.
4. **Firmware producer:** time quality, boot ID/sequence, DHT quality, rain counter epoch, minute accumulator và bounded offline buffer. Chỉ bật publisher v2 sau gate receiver.

## Ngoài phạm vi

Không triển khai live lease/app cache đầy đủ, không dual-write cùng sample vào hai history pipeline, không rollout toàn bộ board đồng thời.

## Phụ thuộc và thứ tự

P00/P01, registry binding cần thiết từ P03. Receiver/fixtures có thể phát triển song song transport; rollout bắt buộc: staging receiver → simulator → một firmware canary → nhóm nhỏ.

## Nghiệm thu

- Log cùng identity chỉ thành một row; conflict payload được ghi nhận.
- Live không ghi history; DB failure không trả trạng thái persisted; queue/concurrency có giới hạn.
- Offline/backlog, reconnect, fragmented/oversize JSON theo policy; không mất identity/time/quality.
- Publisher v2 không chạy trước receiver; firmware cũ tiếp tục được adapter phục vụ.
- Heap/stack/watchdog/packet-size được đo trên board, không chỉ unit test.

## Rollout/rollback

Dual-read/receiver trước publisher. Mốc cutover xác định theo station; không trộn raw 5s với log phút. Rollback giữ reader legacy và provenance để không double-count.

## Đề xuất nâng cấp firmware sau P04 (Deferred)

1. **Chuyển `PubSubClient` (QoS 0) sang `esp_mqtt_client` (ESP-MQTT) QoS 1:**
   - Hiện `PubSubClient` chỉ hỗ trợ publish QoS 0 (không có `PUBACK` từ broker cho từng bản tin gửi lên). Khi yêu cầu bảo đảm giao nhận ở mức transport cho production diện rộng, thay bằng `esp_mqtt_client` để bật QoS 1 + kiểm tra heap/reconnect/fragmentation trên board thật.
2. **Lưu offline backlog xuống Flash/LittleFS/NVS có giới hạn wear:**
   - Hiện firmware dùng RAM ring buffer 12 slot (đủ bù tối đa 12 phút khi mất Wi-Fi/MQTT tạm thời, nhưng mất dữ liệu chưa gửi nếu mất điện đột ngột). Khi cần bảo toàn log phút qua mất điện, chuyển backlog sang LittleFS/NVS với ring buffer cố định và wear-leveling guard.

**Tham chiếu:** `FW-PLAN-02–05`, `BE-PLAN-02`, `CROSS-01/03`; MQ-01–06, DT-01/02.
