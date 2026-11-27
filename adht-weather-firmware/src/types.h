#ifndef TYPES_H
#define TYPES_H

#include <Arduino.h>

// Weather telemetry data
struct WeatherData {
    float temperature = 0.0f;     // Celsius
    float humidity = 0.0f;        // Percentage %
    float rain_rate = 0.0f;       // mm/h
    float rain_total = 0.0f;      // Total mm in session
    float wind_speed = 0.0f;      // m/s
    float wind_max = 0.0f;        // Peak m/s
    uint32_t last_updated = 0;    // millis()
    bool dht_ok = true;           // False if DHT11 fails continuously > 15s
    bool has_valid_dht = false;   // True after at least one valid DHT11 read
};

// Alert and Threshold configuration
struct SystemConfig {
    uint32_t version = 0;
    float temp_max_alert = 38.0f;  // Alert when temp >= threshold
    float temp_min_alert = 10.0f;  // Alert when temp <= threshold
    float humi_max_alert = 90.0f;  // Alert when humi >= threshold
    float wind_max_alert = 15.0f;  // Alert when wind >= 15 m/s (strong wind)
    float rain_max_alert = 30.0f;  // Alert when rain >= 30 mm/h (heavy storm, khớp Backend/App)
    bool buzzer_enabled = true;
    bool auto_warning_enabled = true;
};

// Versioned NVS record for SystemConfig with CRC-32 integrity check
struct SystemConfigNvsRecord {
    static constexpr uint16_t MAGIC_VERSION = 1;
    uint16_t magic = MAGIC_VERSION;
    SystemConfig config;
    uint32_t crc32 = 0;
};

// Partial configuration update received via MQTT
struct ConfigUpdatePatch {
    char request_id[65] = {0};
    char expires_at[32] = {0};
    bool has_version = false;
    uint32_t version = 0;
    bool has_temp_max = false;
    float temp_max = 0.0f;
    bool has_temp_min = false;
    float temp_min = 0.0f;
    bool has_humi_max = false;
    float humi_max = 0.0f;
    bool has_wind_max = false;
    float wind_max = 0.0f;
    bool has_rain_max = false;
    float rain_max = 0.0f;
    bool has_auto_warning = false;
    bool auto_warning = true;
    bool has_buzzer = false;
    bool buzzer = true;
};

// System network & connection status (POD struct safe to copy across cores)
struct NetworkStatus {
    bool wifi_connected = false;
    bool mqtt_connected = false;
    bool provisioning_active = false;
    int wifi_rssi = 0;
    char ip_address[16] = "0.0.0.0";
    char ap_ssid[24] = "";
    char ap_pass[16] = "";
    char ap_url[24] = "http://192.168.4.1";
    uint32_t last_db_sync = 0;
};

// Versioned NVS record for Wi-Fi credentials with integrity checksum
struct WifiCredentialsRecord {
    static constexpr uint16_t CURRENT_VERSION = 1;
    uint16_t version = CURRENT_VERSION;
    char ssid[33] = {0};
    char password[65] = {0};
    uint32_t crc32 = 0;
};

// P04 v2 minute-log accumulator snapshot (POD struct safe to copy across cores)
struct MinuteLogSample {
    uint32_t window_sequence = 0;
    uint32_t uptime_start_ms = 0;
    uint32_t uptime_end_ms = 0;
    int64_t epoch_start_sec = 0;
    int64_t epoch_end_sec = 0;
    bool clock_synchronized = false;

    float temp_sum = 0.0f;
    float temp_min = 0.0f;
    float temp_max = 0.0f;
    float temp_latest = 0.0f;

    float humi_sum = 0.0f;
    float humi_min = 0.0f;
    float humi_max = 0.0f;
    float humi_latest = 0.0f;

    float wind_sum = 0.0f;
    float wind_min = 0.0f;
    float wind_max = 0.0f;
    float wind_latest = 0.0f;

    uint16_t dht_expected_count = 0;
    uint16_t dht_valid_count = 0;
    uint16_t wind_expected_count = 0;
    uint16_t wind_valid_count = 0;

    uint32_t rain_reset_epoch = 0;
    uint32_t tip_count_start = 0;
    uint32_t tip_count_end = 0;
};

#endif // TYPES_H

