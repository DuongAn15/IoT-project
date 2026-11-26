# P03 — Station identity và catalogue

**Trạng thái:** Implemented on branch `feat/p03-station-identity-and-catalogue` (P03a identity/race-guard & P03b catalogue/pagination/access filter verified)
**Mục tiêu:** mọi màn hình và request dùng station ID thật, không đổi nhãn trên dữ liệu của trạm khác; catalogue có nguồn từ backend.

## Phạm vi

### P03a — Sửa lỗi identity hiện tại
- Chọn/lưu `selectedStationId`, callback gửi ID thay vì tên hiển thị.
- Dashboard, Settings, weather repository và command/config cùng đọc một ID.
- Không cho response cũ của station A ghi đè UI/cache sau khi chuyển sang B; kiểm tra ID của response/cache.
- Cache latest theo station; fallback cache phải xác nhận đúng ID.

### P03b — Catalogue và model station/device
- Backend station/device/deployment registry, quyền, alias legacy và pagination.
- App tải/cache catalogue được phép; tên/location/timezone lấy từ metadata, có fallback offline.
- MAC là thuộc tính, không phải identity/credential.

## Ngoài phạm vi

Không gửi config/command mới tới trạm chưa được resolve/authorized; không migrate history cache v2 trong P03a.

## Phụ thuộc và thứ tự

P00. P03a có thể chạy song song P01 và P02. P03b cần API auth của P01 và schema/contract registry được review trước.

## Nghiệm thu

- A→B, B offline, A response về muộn: không hiển thị dữ liệu A dưới tên B.
- Latest file/cache không dùng chung sai trạm; Settings và Dashboard cùng station ID.
- Catalogue pagination/cap thấp không thiếu thiết bị; quyền chỉ trả station được phép.
- Legacy ID resolve nhất quán trong thời hạn tương thích.

## Rollout/rollback

P03a giữ map cũ làm fallback nhưng ID là nguồn lựa chọn. P03b deploy adapter/backend trước app catalogue; không drop cột/alias hoặc đổi PK hiện hữu trong bước đầu.

**Tham chiếu:** `APP-PLAN-01`, `BE-PLAN-01`; AP-02/03, API-04/06.
