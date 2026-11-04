# 🧪 ADHT Weather Station - Companion Node Simulator

Công cụ giả lập các trạm thời tiết ESP32 ảo chạy **song song và đồng hành** cùng trạm phần cứng thật (`adht_weather_01`).

---

## 🎯 Phân bổ Hệ Thống Trạm

* **`adht_weather_01` (Trạm Vật lý thật)**: Mạch ESP32 thật cắm dây của bạn, đo nhiệt ẩm, mưa, gió thực tế.
* **`adht_weather_02` (Trạm Ảo 1 - Nắng Nóng)**: Nhiệt độ cao ($38.6^\circ\text{C}$), kích hoạt cảnh báo `HIGH TEMP!` trên App.
* **`adht_weather_03` (Trạm Ảo 2 - Mưa Dông)**: Mưa to ($32\text{ mm/h}$) và gió giật ($8.5\text{ m/s}$), kích hoạt cảnh báo `HEAVY RAIN!` và `STRONG WIND!`.

👉 **Tại sao mặc định trạm ảo không chạy `adht_weather_01`?**
Trong giao thức MQTT, nếu 2 máy cùng đăng nhập bằng chung 1 `Client ID`, Broker sẽ lập tức ngắt kết nối của thiết bị trước đó (Client Takeover). Vì bạn đã có ESP32 thật chạy `adht_weather_01`, script giả lập sẽ chạy các trạm từ `02` trở đi để không xung đột với phần cứng thật của bạn.

---

## 🚀 Hướng Dẫn Sử Dụng

### 1. Cài đặt thư viện yêu cầu (Chỉ cần 1 thư viện)

```bash
pip install -r tools/requirements.txt
```

### 2. Chạy mặc định (Chu kỳ 5.0 giây, 2 trạm ảo đồng hành)

```bash
python3 tools/simulate_nodes.py
```

*(Kết hợp với ESP32 thật của bạn, hệ thống sẽ có đúng **3 trạm** hiển thị trên Supabase và Mobile App).*

Script tự tìm `.env` ở firmware, root rồi backend (chọn file đầu tiên tồn tại).
Biến môi trường của terminal được ưu tiên hơn giá trị trong file.
Để chọn chính xác cấu hình, kể cả file tên `env` không có dấu chấm:

```bash
python3 tools/simulate_nodes.py --env-file adht-weather-backend/.env
# Hoặc:
python3 tools/simulate_nodes.py --env-file adht-weather-firmware/env
```

EMQX Cloud thường dùng `MQTT_BROKER_PORT=8883` và `MQTT_USE_TLS=true`
(TLS mặc định bật). `MQTT_BROKER_HOST` chỉ chứa hostname, không thêm `mqtts://`.
Chứng chỉ TLS được xác thực; nếu broker dùng CA riêng, đặt `MQTT_CA_FILE`
thành đường dẫn file CA (đường dẫn tương đối tính từ thư mục chạy lệnh).

Nếu gặp timeout, kiểm tra file được in ở dòng `[ENV]`, endpoint/cổng trong
dashboard EMQX và firewall/VPN. Timeout có thể xảy ra ở TCP hoặc TLS, chưa đủ
để kết luận sai mật khẩu. Simulator tự thử lại khi kết nối thất bại; chỉ dòng
`Kết nối ... thành công` mới xác nhận đã được broker chấp nhận.

### 3. Tùy chọn nâng cao

```bash
# Đổi chu kỳ gửi sang 3.0 giây nếu muốn test tốc độ cao:
python3 tools/simulate_nodes.py --interval 3.0

# Chỉ chạy 1 trạm ảo duy nhất (adht_weather_02):
python3 tools/simulate_nodes.py -n 1

# Khi KHÔNG cắm ESP32 thật mà muốn giả lập cả adht_weather_01:
python3 tools/simulate_nodes.py --include-node1
```

---

## 💡 Thử nghiệm tính năng 2 chiều với Mobile App

Khi bạn bấm nút trên App:

* **Bấm còi trạm 02**: Terminal của simulator sẽ in ra:`[adht_weather_02] 🔔 [LỆNH APP] BẬT CÒI CẢNH BÁO (500 ms) -> Bíp... Bíp...`
* **Đổi ngưỡng trạm 02**: Simulator sẽ lưu vào bộ nhớ ảo và in ra:`[adht_weather_02] ⚙️ ĐÃ LƯU CẤU HÌNH VÀO NVS FLASH: {"temp_max": 39.5, ...}`
* **Trạm thật `adht_weather_01`**: Còi thật trên mạch sẽ kêu tiếng bíp thực tế!
