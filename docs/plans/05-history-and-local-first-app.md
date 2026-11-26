# P05 — History, aggregation và local-first app

**Trạng thái:** Planned
**Mục tiêu:** API và biểu đồ biểu diễn đúng đơn vị/thống kê; app sync phần thiếu, cache đúng station và không xóa nội dung khi refresh.

## Phạm vi

- Chốt semantics ngay: `rain_rate` là mm/h; không gọi/cộng nó thành `totalRainfall` mm. UI tạm thời hiển thị đúng rate cho legacy data; chỉ đưa total amount khi có counter/window đủ tin cậy.
- Backend fixed bucket origin, half-open ranges, timezone trạm, weighted stats, min/max/coverage/revision và range/page caps.
- Protocol v2 cung cấp rain tip counter + reset epoch để tính rain amount có provenance; dữ liệu legacy không đủ thông tin phải đánh dấu unknown/estimated.
- API daily/history hỗ trợ incremental range; query plan/latency/rows được đo.
- App cache key theo station/series/resolution/timezone/version; migration, local-first, single-flight, chống response cũ; summary hôm nay partial riêng.

## Ngoài phạm vi

Không tự coi dữ liệu rate cũ là amount; không ép Timescale; không làm cache v2 trước khi contract API/bucket ổn định.

## Phụ thuộc và thứ tự

P00 và schema payload P04. Backend API/fixtures đi trước app migration; immediate UI unit correction có thể làm sớm như hotfix riêng.

## Nghiệm thu

- Fixture rain rate/amount, reset, missing window, timezone, midnight và count không đều cho kết quả đúng.
- Bucket key ổn định giữa các lần refresh; không mất min/max khi rollup.
- Pagination/correction không bỏ gap; cache cursor commit cùng rows.
- Offline hiển thị cache đúng trạm; API lỗi một resource không xóa dữ liệu resource khác.
- Một refresh không gọi cùng bộ API hai lần; stale response station cũ bị loại.

## Rollout/rollback

API giữ alias/response legacy có thời hạn; cache migration additive và có fallback. Không cộng dữ liệu cũ/mới nếu semantics khác nhau.

**Tham chiếu:** `BE-PLAN-03`, `APP-PLAN-02–04`, `CROSS-02`; DT-03–07, AP-01/03–05.
