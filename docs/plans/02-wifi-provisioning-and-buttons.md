# P02 — Wi-Fi provisioning và nút vật lý

**Trạng thái:** Implemented on branch `feat/p02-wifi-provisioning-and-buttons` (code/build verified; board physical acceptance pending)
**Mục tiêu:** bỏ Wi-Fi credentials compile-time; cho phép setup lần đầu và đổi mạng bằng điện thoại, không mất credentials tốt khi nhập sai.

## Phạm vi

- NVS không có credentials: mở AP provisioning WPA2 với password ngẫu nhiên tạm thời; hiển thị SSID/password/URL local trên OLED.
- Credentials đã có: STA tự kết nối khi boot. Mất router chỉ retry có backoff/offline; không tự mở AP liên tục.
- Đổi Wi-Fi: SET giữ đủ 8 giây, OLED báo; thả sau ngưỡng để xác nhận portal. Thử credentials mới trước khi thay credentials hiện tại; lỗi thì giữ credentials cũ; thành công thì lưu record có version/checksum, read-back rồi reboot.
- Button active-low: UP GPIO35 nhấn ngắn chuyển trang 1→2→3; DOWN GPIO34 chuyển ngược; chặn tại biên. SET tap đánh thức màn hình; giữ 2 đến dưới 8 giây snooze khi thả; giữ ≥8 giây và thả vào provisioning.
- Phần cứng đã được người dùng xác nhận GPIO35/34: idle=1, pressed=0. Đây là input-only, có pull-up ngoài; dùng `INPUT`, không dùng `INPUT_PULLUP`.
- Debounce/wrap-safe duration. Task đọc nút gửi request/queue; chỉ taskNetwork/WifiManager thay đổi Wi-Fi/AP. Nút UP/DOWN hiện chưa có handler, macro đang tắt.

## Ngoài phạm vi

Không mở cấu hình Wi-Fi qua Internet/API cloud; không tự phát AP khi router lỗi tạm thời; không đổi MQTT transport trong cùng PR.

## Phụ thuộc và thứ tự

P00 và xác nhận board/wiring trước. Có thể song song P01 nếu thay đổi firmware ở PR/file tách biệt; tránh gộp Wi-Fi portal và MQTT transport rewrite.

## Nghiệm thu

- NVS trống mở portal; reboot bình thường tự STA, không phát AP.
- Router down không làm sensor/alarm dừng và không bật AP ngoài ý muốn.
- Wi-Fi password sai không ghi đè credentials tốt; cấu hình đúng reconnect sau reboot.
- AP WPA2, timeout, không log secret; portal có URL fallback nếu captive portal không bật.
- Button boundary, bounce, 2–8s snooze, ≥8s provisioning, UP/DOWN trang 1/3 không double-trigger.
- Test mất điện khi ghi NVS và xác nhận sensor task/watchdog không bị block.

## Rollout/rollback

Canary trên board có thể truy cập nút/OLED. Giữ phương án phục hồi bằng thao tác vật lý; không xóa credentials tốt trước khi credentials mới được xác minh.

**Tham chiếu:** `FW-PLAN-07`, `CROSS-04`, firmware `config.h`, `wifi_manager.*`, `main.cpp`.
