# 🦁 ADHT Weather Station - NestJS Backend Gateway (Boilerplate / Scaffold)

Đây là **bộ khung kiến trúc (Scaffold)** của phân hệ **Máy chủ Trung tâm (Backend Gateway)** được khởi tạo bằng **NestJS 10 (TypeScript)** và đóng gói sẵn **Docker Compose**.

Bộ khung này thiết lập sẵn cấu trúc chuẩn, các DTO định kiểu dữ liệu, các Controller khai báo routes kèm Swagger UI, và để ngỏ các vị trí đánh dấu `// TODO` trong Service để lập trình viên tự do viết code nghiệp vụ.

---

## 📂 Bản Đồ Cấu Trúc Khung Dự Án

```text
adht-weather-backend/
├── Dockerfile                  # Multi-stage build Node.js 20 Alpine
├── docker-compose.yml          # Cấu hình container chạy production
├── package.json                # Dependencies: NestJS, Swagger, WebSockets, MQTT, Supabase, Firebase
├── tsconfig.json               # Cấu hình TypeScript
├── nest-cli.json               # Cấu hình Nest CLI
├── .env.example                # Template biến môi trường
├── README.md                   # Tài liệu tổng quan
├── DEVELOPMENT_GUIDE.md        # 📖 Hướng dẫn chi tiết & checklist TODO cho bạn dev
└── src/
    ├── main.ts                 # Bootstrap: CORS, Global Prefix (/api), Swagger UI (/docs), ValidationPipe
    ├── app.module.ts           # Root Module liên kết các phân hệ
    ├── config/                 # Đọc và định kiểu cấu hình biến môi trường
    ├── common/                 # Filter bắt lỗi toàn cục & Interceptor chuẩn hóa response
    └── modules/
        ├── mqtt/               # 📌 [TODO] MqttService: Kết nối Broker MQTTS 8883, subscribe & publish
        ├── database/           # 📌 [TODO] SupabaseService: Lưu PostgreSQL & thuật toán Downsampling biểu đồ
        ├── notifications/      # 📌 [TODO] NotificationsService: Kiểm tra thiên tai & gọi Firebase FCM
        ├── websocket/          # 📌 [TODO] TelemetryGateway: Kênh WebSocket /ws/telemetry phát realtime
        ├── telemetry/          # 📌 [TODO] TelemetryController: Nhận Webhook từ EMQX Cloud Rule Engine
        ├── weather/            # 📌 [TODO] WeatherController: API latest, history làm mịn & dự báo 3 ngày
        └── devices/            # 📌 [TODO] DevicesController: API gửi lệnh còi/LED & cài đặt ngưỡng ESP32
```

---

## 🚀 Khởi Động Nhanh Khung Dự Án (Hỗ trợ cả Bun và NPM)

Dự án tương thích hoàn toàn với cả **Bun** (cực nhanh, đã có sẵn trên máy) và **NPM / Node.js**:

### Lựa chọn 1: Dùng Bun (Khuyên dùng - Cài đặt siêu nhanh)
```bash
cd adht-weather-backend

# 1. Cài đặt các gói thư viện
bun install

# 2. Tạo file cấu hình từ template mẫu
cp .env.example .env

# 3. Khởi chạy ở chế độ Hot-reload (Watch mode)
bun dev
# (hoặc: bun run start:dev)
```

### Lựa chọn 2: Dùng NPM (Chuẩn Node.js)
```bash
cd adht-weather-backend

# 1. Cài đặt các gói thư viện
npm install

# 2. Tạo file cấu hình từ template mẫu
cp .env.example .env

# 3. Khởi chạy ở chế độ Hot-reload (Watch mode)
npm run start:dev
```

- **Trang tài liệu Swagger UI**: `http://localhost:8000/docs`
- **Kênh WebSocket**: `ws://localhost:8000/ws/telemetry`

---

## 📖 Hướng Dẫn Chi Tiết
Vui lòng xem chi tiết danh sách checklist `TODO` và đặc tả dữ liệu tại:  
👉 **[`DEVELOPMENT_GUIDE.md`](DEVELOPMENT_GUIDE.md)**
