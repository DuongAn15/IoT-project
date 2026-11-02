#!/usr/bin/env python3
"""
====================================================================
ADHT SMART WEATHER STATION - COMPANION NODE SIMULATOR
====================================================================
Script mô phỏng các trạm thời tiết ESP32 ảo (chạy song song với trạm
vật lý adht_weather_01) gửi dữ liệu lên EMQX Cloud và nhận lệnh từ App.

Lưu ý:
- Trạm 01 (adht_weather_01) là thiết bị phần cứng thật của bạn.
- Mặc định script sẽ chạy 2 trạm ảo:
    * Node 2 (adht_weather_02): Nắng gắt, cảnh báo nhiệt cao (>38°C)
    * Node 3 (adht_weather_03): Mưa dông bão, cảnh báo mưa to & gió giật
- Tổng cộng hệ thống sẽ có đúng 3 trạm (1 thật + 2 ảo) để kiểm thử App.
- Chu kỳ gửi mặc định: 5.0 giây (đồng bộ với ESP32 thật).
====================================================================
"""

import os
import sys

# Tự động nạp site-packages từ PlatformIO virtualenv hoặc user local nếu có
def _inject_possible_paths():
    home = os.path.expanduser("~")
    # 1. PlatformIO penv
    penv_lib = os.path.join(home, ".platformio", "penv", "lib")
    if os.path.isdir(penv_lib):
        for entry in os.listdir(penv_lib):
            sp = os.path.join(penv_lib, entry, "site-packages")
            if os.path.isdir(sp) and sp not in sys.path:
                sys.path.insert(0, sp)
    # 2. User local
    local_lib = os.path.join(home, ".local", "lib")
    if os.path.isdir(local_lib):
        for entry in os.listdir(local_lib):
            sp = os.path.join(local_lib, entry, "site-packages")
            if os.path.isdir(sp) and sp not in sys.path:
                sys.path.insert(0, sp)

_inject_possible_paths()

import ssl
import time
import json
import random
import signal
import argparse
import threading
from typing import Dict, Any

try:
    import paho.mqtt.client as mqtt
except ImportError:
    print("\n[!] Không tìm thấy thư viện paho-mqtt trong môi trường Python này.")
    print("    Gợi ý giải pháp:")
    print("    1. Chạy trực tiếp bằng Python của PlatformIO (nơi đã có sẵn thư viện):")
    print("       ~/.platformio/penv/bin/python tools/simulate_nodes.py")
    print("    2. Hoặc cài vào Python hệ thống:")
    print("       python3 -m pip install paho-mqtt --break-system-packages\n")
    sys.exit(1)

# ANSI Colors
C_RESET   = "\033[0m"
C_BOLD    = "\033[1m"
C_RED     = "\033[31m"
C_GREEN   = "\033[32m"
C_YELLOW  = "\033[33m"
C_BLUE    = "\033[34m"
C_MAGENTA = "\033[35m"
C_CYAN    = "\033[36m"
C_WHITE   = "\033[37m"

def find_and_load_env() -> Dict[str, str]:
    """Tìm và đọc file .env từ thư mục firmware hoặc thư mục gốc."""
    candidate_paths = [
        os.path.join(os.path.dirname(__file__), "..", "adht-weather-firmware", ".env"),
        os.path.join(os.path.dirname(__file__), "..", ".env"),
        os.path.join(os.getcwd(), "adht-weather-firmware", ".env"),
        os.path.join(os.getcwd(), ".env"),
    ]
    env_vars = {}
    found_path = None
    for p in candidate_paths:
        abs_p = os.path.abspath(p)
        if os.path.exists(abs_p):
            found_path = abs_p
            break

    if found_path:
        print(f"{C_CYAN}[ENV] Đang tải cấu hình từ: {found_path}{C_RESET}")
        with open(found_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                env_vars[k.strip()] = v.strip().strip("'\"")
    else:
        print(f"{C_YELLOW}[ENV] Không tìm thấy file .env, sử dụng cấu hình mặc định.{C_RESET}")
    return env_vars

_env = find_and_load_env()
BROKER_HOST = _env.get("MQTT_BROKER_HOST", _env.get("MQTT_HOST", "xxxxxxxx.ala.asia-southeast1.emqxsl.com"))
BROKER_PORT = int(_env.get("MQTT_BROKER_PORT", _env.get("MQTT_PORT", 8883)))
BROKER_USER = _env.get("MQTT_USERNAME", _env.get("MQTT_USER", "adht_device"))
BROKER_PASS = _env.get("MQTT_PASSWORD", _env.get("MQTT_PASS", "Your_Mqtt_Password"))

# Danh mục cấu hình các Trạm Ảo (Tránh trùng với adht_weather_01 thật)
VIRTUAL_NODE_PROFILES = [
    {
        "id": "adht_weather_02",
        "name": "Trạm 02 Ảo - Nắng Nóng (Cảnh báo Nhiệt cao > 38°C)",
        "color": C_YELLOW,
        "base_temp": 38.6,
        "base_humi": 45.0,
        "base_wind": 2.6,
        "base_rain": 0.0,
        "temp_var": 0.3,
        "humi_var": 0.5,
        "wind_var": 0.4,
    },
    {
        "id": "adht_weather_03",
        "name": "Trạm 03 Ảo - Mưa Dông (Cảnh báo Mưa to & Gió giật)",
        "color": C_CYAN,
        "base_temp": 24.5,
        "base_humi": 92.0,
        "base_wind": 8.5,   # Gió lớn
        "base_rain": 32.0,  # Mưa to 32 mm/h
        "temp_var": 0.2,
        "humi_var": 0.4,
        "wind_var": 1.2,
    },
    {
        "id": "adht_weather_04",
        "name": "Trạm 04 Ảo - Cao Nguyên (Mát mẻ & Độ ẩm cao)",
        "color": C_MAGENTA,
        "base_temp": 19.8,
        "base_humi": 85.0,
        "base_wind": 3.4,
        "base_rain": 2.5,
        "temp_var": 0.2,
        "humi_var": 0.3,
        "wind_var": 0.5,
    }
]

# Profile dự phòng cho Node 1 (chỉ dùng khi người dùng chủ động yêu cầu mô phỏng Node 1)
NODE_01_FALLBACK_PROFILE = {
    "id": "adht_weather_01",
    "name": "Trạm 01 (Mô phỏng thay thế Node Vật lý)",
    "color": C_GREEN,
    "base_temp": 28.5,
    "base_humi": 68.0,
    "base_wind": 2.2,
    "base_rain": 0.0,
    "temp_var": 0.3,
    "humi_var": 0.5,
    "wind_var": 0.4,
}

class SimulatedEsp32Node:
    """Đại diện cho 1 thiết bị ESP32 ảo với đầy đủ cảm biến và giao tiếp MQTTS."""

    def __init__(self, profile: Dict[str, Any], host: str, port: int, user: str, password: str, interval: float = 5.0):
        self.profile = profile
        self.device_id = profile["id"]
        self.name = profile["name"]
        self.color = profile["color"]
        self.host = host
        self.port = port
        self.user = user
        self.password = password
        self.interval = interval

        self.temp = profile["base_temp"]
        self.humi = profile["base_humi"]
        self.wind_speed = profile["base_wind"]
        self.wind_max = profile["base_wind"] * 1.3
        self.rain_rate = profile["base_rain"]
        self.rain_total = 8.5 if profile["base_rain"] > 0 else 0.0
        self.rssi = -60 + random.randint(-8, 5)
        self.start_time = time.time()

        self.sys_config = {
            "temp_max": 38.0,
            "temp_min": 10.0,
            "humi_max": 90.0,
            "wind_max": 15.0,
            "rain_max": 50.0,
            "auto_warning": True,
            "buzzer": True
        }

        self.led_state = False
        self.is_connected = False
        self.running = True

        try:
            from paho.mqtt.enums import CallbackAPIVersion
            self.client = mqtt.Client(CallbackAPIVersion.VERSION2, client_id=self.device_id)
        except (ImportError, AttributeError):
            self.client = mqtt.Client(client_id=self.device_id)

        self.client.username_pw_set(self.user, self.password)

        context = ssl.create_default_context()
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE
        self.client.tls_set_context(context)

        # LWT riêng của node (QoS 1, retain True)
        lwt_payload = json.dumps({"status": "offline", "device": self.device_id})
        self.client.will_set(f"adht/weather/{self.device_id}/status", lwt_payload, qos=1, retain=True)

        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect
        self.client.on_message = self._on_message

    def _log(self, msg: str, color: str = None):
        c = color or self.color
        print(f"{c}[{self.device_id}]{C_RESET} {msg}")

    def _on_connect(self, client, userdata, flags, rc, properties=None):
        rc_code = rc if isinstance(rc, int) else getattr(rc, "value", rc)
        if rc_code == 0:
            self.is_connected = True
            self._log(f"✅ Kết nối MQTTS thành công ({self.host}:{self.port})", C_GREEN)

            # Báo Online
            online_payload = json.dumps({
                "status": "online",
                "device": self.device_id,
                "ip": f"192.168.1.{random.randint(10, 250)}"
            })
            self.client.publish(f"adht/weather/{self.device_id}/status", online_payload, qos=1, retain=True)

            # Subscribe nhận lệnh điều khiển & cấu hình riêng cho từng node (QoS 1)
            self.client.subscribe("adht/weather/command", qos=1)
            self.client.subscribe("adht/weather/config", qos=1)
            self.client.subscribe(f"adht/weather/{self.device_id}/command", qos=1)
            self.client.subscribe(f"adht/weather/{self.device_id}/config", qos=1)
        else:
            self._log(f"❌ Kết nối thất bại, mã lỗi = {rc_code}", C_RED)

    def _on_disconnect(self, client, userdata, rc, properties=None):
        self.is_connected = False
        self._log(f"⚠️ Mất kết nối MQTT (code={rc})", C_YELLOW)

    def _on_message(self, client, userdata, msg):
        topic = msg.topic
        payload_str = msg.payload.decode("utf-8", errors="ignore")

        if "command" in topic:
            try:
                data = json.loads(payload_str)
                # Kiểm tra xem lệnh có chỉ định device_id cụ thể không
                target = data.get("device_id", "")
                if target and target != self.device_id:
                    return  # Không phải lệnh cho node này

                cmd = data.get("cmd", "")
                arg = data.get("arg", "")
                self._handle_command(cmd, arg)
            except Exception as e:
                self._log(f"Lỗi parse command JSON: {e}", C_RED)

        elif "config" in topic:
            try:
                data = json.loads(payload_str)
                target = data.get("device_id", "")
                if target and target != self.device_id:
                    return

                for k in self.sys_config.keys():
                    if k in data:
                        self.sys_config[k] = data[k]
                self._log(f"⚙️ ĐÃ LƯU CẤU HÌNH VÀO NVS FLASH: {json.dumps(self.sys_config)}", C_MAGENTA)
            except Exception as e:
                self._log(f"Lỗi parse config JSON: {e}", C_RED)

    def _handle_command(self, cmd: str, arg: str):
        if cmd == "buzzer":
            ms = int(arg) if arg.isdigit() else 500
            self._log(f"🔔 [LỆNH APP] BẬT CÒI CẢNH BÁO ({ms} ms) -> Bíp... Bíp...", C_RED)
        elif cmd == "led":
            self.led_state = not self.led_state
            st = "BẬT (ON)" if self.led_state else "TẮT (OFF)"
            self._log(f"💡 [LỆNH APP] ĐỔI TRẠNG THÁI ĐÈN LED -> {st}", C_YELLOW)
        elif cmd == "reset":
            self._log(f"🔄 [LỆNH APP] KHỞI ĐỘNG LẠI ESP32 (REBOOT) THEO YÊU CẦU...", C_CYAN)
            self.client.publish(f"adht/weather/{self.device_id}/status", json.dumps({"status": "offline", "device": self.device_id}), qos=1, retain=True)
            time.sleep(1.5)
            self.start_time = time.time()
            self.client.publish(f"adht/weather/{self.device_id}/status", json.dumps({"status": "online", "device": self.device_id}), qos=1, retain=True)
            self._log(f"✅ ESP32 ĐÃ KHỞI ĐỘNG XONG VÀ ONLINE TRỞ LẠI!", C_GREEN)
        else:
            self._log(f"❓ Nhận lệnh không xác định: cmd='{cmd}', arg='{arg}'", C_YELLOW)

    def _update_physics(self):
        p = self.profile
        self.temp += random.uniform(-p["temp_var"], p["temp_var"])
        self.temp = max(15.0, min(45.0, self.temp))

        self.humi += random.uniform(-p["humi_var"], p["humi_var"])
        self.humi = max(20.0, min(99.0, self.humi))

        self.wind_speed += random.uniform(-p["wind_var"], p["wind_var"])
        self.wind_speed = max(0.0, min(35.0, self.wind_speed))
        if self.wind_speed > self.wind_max:
            self.wind_max = self.wind_speed

        if p["base_rain"] > 0:
            self.rain_rate += random.uniform(-2.0, 2.0)
            self.rain_rate = max(5.0, min(80.0, self.rain_rate))
            self.rain_total += (self.rain_rate / 3600.0) * self.interval
        else:
            self.rain_rate = 0.0

    def start(self):
        try:
            self.client.connect(self.host, self.port, keepalive=60)
            self.client.loop_start()
        except Exception as e:
            self._log(f"Lỗi kết nối tới broker: {e}", C_RED)

        t = threading.Thread(target=self._telemetry_loop, daemon=True)
        t.start()

    def _telemetry_loop(self):
        while self.running:
            time.sleep(self.interval)
            if not self.is_connected:
                continue

            self._update_physics()
            uptime_sec = int(time.time() - self.start_time)

            payload = {
                "device_id": self.device_id,
                "temp": round(self.temp, 1),
                "humi": round(self.humi, 1),
                "rain_rate": round(self.rain_rate, 2),
                "rain_total": round(self.rain_total, 2),
                "wind_speed": round(self.wind_speed, 1),
                "wind_max": round(self.wind_max, 1),
                "rssi": self.rssi,
                "uptime": uptime_sec
            }

            raw_json = json.dumps(payload)
            # Publish QoS 0 lên topic chung (EMQX Rule Engine tự ghi Supabase)
            self.client.publish("adht/weather/telemetry", raw_json, qos=0)
            # Publish topic riêng của node
            self.client.publish(f"adht/weather/{self.device_id}/telemetry", raw_json, qos=0)

            alert_str = ""
            if self.temp >= self.sys_config["temp_max"]:
                alert_str = f" {C_RED}[🔥 HIGH TEMP!]{C_RESET}"
            elif self.wind_speed >= self.sys_config["wind_max"]:
                alert_str = f" {C_YELLOW}[💨 STRONG WIND!]{C_RESET}"
            elif self.rain_rate >= self.sys_config["rain_max"]:
                alert_str = f" {C_CYAN}[🌧️ HEAVY RAIN!]{C_RESET}"

            self._log(
                f"📡 Telemetry ({self.interval}s) -> T: {payload['temp']}°C | H: {payload['humi']}% | "
                f"Gió: {payload['wind_speed']} m/s | Mưa: {payload['rain_rate']} mm/h{alert_str}"
            )

    def stop(self):
        self.running = False
        if self.is_connected:
            self._log("Đang gửi bản tin Offline và ngắt kết nối...", C_YELLOW)
            self.client.publish(f"adht/weather/{self.device_id}/status", json.dumps({"status": "offline", "device": self.device_id}), qos=1, retain=True)
            time.sleep(0.3)
        self.client.loop_stop()
        self.client.disconnect()


def main():
    parser = argparse.ArgumentParser(
        description="Trình mô phỏng trạm thời tiết ESP32 ảo chạy đồng hành cùng trạm thật adht_weather_01"
    )
    parser.add_argument(
        "-n", "--virtual-nodes",
        type=int,
        default=2,
        choices=[1, 2, 3],
        help="Số lượng trạm ảo cần chạy (1: Chỉ adht_weather_02; 2: adht_weather_02 + 03; 3: thêm adht_weather_04; Mặc định: 2)"
    )
    parser.add_argument(
        "-i", "--interval",
        type=float,
        default=5.0,
        help="Chu kỳ phát telemetry tính bằng giây (Mặc định: 5.0 giây, đồng bộ với ESP32 thật)"
    )
    parser.add_argument(
        "--include-node1",
        action="store_true",
        help="Mô phỏng cả adht_weather_01 (Chỉ dùng khi KHÔNG cắm ESP32 thật để tránh xung đột Client ID)"
    )
    args = parser.parse_args()

    print(f"\n{C_BOLD}{C_BLUE}======================================================{C_RESET}")
    print(f"{C_BOLD}{C_BLUE}  🌦️ ADHT SMART WEATHER STATION - COMPANION SIMULATOR {C_RESET}")
    print(f"{C_BOLD}{C_BLUE}======================================================{C_RESET}")
    print(f"• Broker:   {C_WHITE}{BROKER_HOST}:{BROKER_PORT}{C_RESET}")
    print(f"• Username: {C_WHITE}{BROKER_USER}{C_RESET}")
    print(f"• Chu kỳ:   {C_GREEN}{args.interval} giây/lần{C_RESET}")

    selected_profiles = []
    if args.include_node1:
        print(f"• Chế độ:   {C_YELLOW}Bao gồm cả adht_weather_01 ảo (ESP32 thật đang TẮT){C_RESET}")
        selected_profiles.append(NODE_01_FALLBACK_PROFILE)
    else:
        print(f"• Trạm thật: {C_GREEN}adht_weather_01 (Phần cứng ESP32 trên bàn của bạn){C_RESET}")
        print(f"• Trạm ảo:   {C_CYAN}{args.virtual_nodes} nodes đồng hành (adht_weather_02, ...){C_RESET}")

    for i in range(args.virtual_nodes):
        selected_profiles.append(VIRTUAL_NODE_PROFILES[i])

    print(f"• Tổng cộng: {C_BOLD}{len(selected_profiles) + (0 if args.include_node1 else 1)} Trạm trong hệ thống{C_RESET}")
    print(f"{C_BOLD}{C_BLUE}======================================================{C_RESET}\n")

    nodes = []
    for profile in selected_profiles:
        node = SimulatedEsp32Node(
            profile=profile,
            host=BROKER_HOST,
            port=BROKER_PORT,
            user=BROKER_USER,
            password=BROKER_PASS,
            interval=args.interval
        )
        nodes.append(node)
        node.start()
        time.sleep(0.4)

    print(f"\n{C_GREEN}⚡ Đã kết nối và phát dữ liệu song song!{C_RESET}")
    print(f"{C_WHITE}👉 Trạm thật: {C_BOLD}adht_weather_01{C_RESET} | Trạm ảo: {C_BOLD}{', '.join([n.device_id for n in nodes])}{C_RESET}")
    print(f"{C_YELLOW}👉 Bấm Ctrl + C để dừng mô phỏng.{C_RESET}\n")

    def handle_exit(sig, frame):
        print(f"\n\n{C_RED}[SIMULATOR] Đang ngắt kết nối các trạm ảo an toàn...{C_RESET}")
        for n in nodes:
            n.stop()
        print(f"{C_GREEN}[SIMULATOR] Đã dừng hoàn tất.{C_RESET}\n")
        sys.exit(0)

    signal.signal(signal.SIGINT, handle_exit)
    signal.signal(signal.SIGTERM, handle_exit)

    while True:
        time.sleep(1)

if __name__ == "__main__":
    main()
