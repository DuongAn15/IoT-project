# P08 — Rollout, observability và vận hành

**Trạng thái:** Planned
**Mục tiêu:** triển khai theo canary có thể quan sát, rollback an toàn, không suy diễn test mock là production readiness.

## Phạm vi

- Compatibility matrix FW/BE/API/cache/NVS trước cutover; staging và canary physical board + simulator.
- Dashboards/alerts: ingest received/valid/committed/duplicate/fail, queue/lag, DB/API latency, operation status, current freshness, heap/watchdog/reconnect.
- Runbook provision/reassign/retire, Wi-Fi setup/recovery, CA/clock, NVS/queue failure, credential rotation, replay/rebuild và incident.
- CI secret scanning, locked dependencies/toolchain, build artifacts; mobile platform smoke tests và hardware failure tests.
- Rollback theo lớp: API adapter, backend receiver, app release, firmware version; schema/NVS mới vẫn đọc an toàn.

## Ngoài phạm vi

Không mở rollout toàn bộ chỉ vì unit tests pass; không drop legacy adapter/topic hoặc xóa dữ liệu để đơn giản hóa rollback.

## Phụ thuộc và thứ tự

Chạy baseline trước mọi rollout; canary P4 trước P5–P7; hoàn tất gate từng plan trước phát hành rộng.

## Nghiệm thu

- Mỗi release có commit, artifact, môi trường, metrics trước/sau và người chịu trách nhiệm.
- Có rollback rehearsal; phiên bản cũ/mới không double-count hoặc gửi side effect ngoài ý muốn.
- Failure matrix: broker/DB mất, cert sai, firmware offline, NVS fail, data trễ, stale app response.
- Không có secret trong Git/artifact/log; thủ tục rotate đã thử ở staging.

## Kết thúc

Chuyển từng plan sang Verified chỉ khi acceptance test đã chạy và có bằng chứng. Mọi giới hạn chưa kiểm chứng được ghi là Blocked/Not verified, không ghi pass.

**Tham chiếu:** mục 16–17 và `CROSS-04` trong [`SYSTEM_REVIEW_AND_ARCHITECTURE.md`](../SYSTEM_REVIEW_AND_ARCHITECTURE.md).
