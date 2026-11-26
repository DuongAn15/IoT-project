# P00 — Baseline và contract

**Trạng thái:** Planned
**Mục tiêu:** tạo baseline đủ tin cậy để các plan tiếp theo làm song song mà không phát triển lệch contract.

## Phạm vi

- Ghi commit/source baseline, toolchain và lệnh build/test cho backend, Flutter, firmware.
- Lưu fixtures versioned cho payload v1 hiện tại và contract v2; định nghĩa identity, timestamp, quality, rain rate/amount, ACK và error semantics.
- Audit read-only schema, grants, RLS, index và giới hạn phân trang Supabase; không thay dữ liệu production.
- Chốt broker/DB/board staging, test credentials riêng, quota và người có quyền truy cập.
- Ghi nhận số đo board hiện có: build, heap/stack nếu đo được, wiring UP/DOWN; giữ secrets ngoài fixtures/log.

## Ngoài phạm vi

Không chạy migration live, không bật publisher v2, không đổi topic production, không commit credential.

## Phụ thuộc và thứ tự

Không có dependency. Là gate đầu vào cho P01–P04. Có thể chia thành PR audit/docs và PR fixtures/tooling.

## Nghiệm thu

- Build/test baseline có kết quả thực, lỗi môi trường tách khỏi lỗi sản phẩm.
- Contract có fixture hợp lệ/không hợp lệ và owner cho từng field.
- Schema/ACL được ghi nhận bằng truy vấn read-only; mọi DDL đề xuất có rollback.
- Staging dùng identity/credential riêng production.

## Rollback

Docs/fixtures/tooling additive; revert PR mà không ảnh hưởng DB hay thiết bị.

**Tham chiếu:** [`SYSTEM_REVIEW_AND_ARCHITECTURE.md`](../SYSTEM_REVIEW_AND_ARCHITECTURE.md), mục 1, 7, 14, 16–18.
