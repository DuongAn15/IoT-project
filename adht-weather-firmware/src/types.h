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
    float temp_max_alert = 38.0f;  // Alert when temp >= threshold
    float temp_min_alert = 10.0f;  // Alert when temp <= threshold
    float humi_max_alert = 90.0f;  // Alert when humi >= threshold
    float wind_max_alert = 15.0f;  // Alert when wind >= 15 m/s (strong wind)
    float rain_max_alert = 30.0f;  // Alert when rain >= 30 mm/h (heavy storm, khớp Backend/App)
    bool buzzer_enabled = true;
    bool auto_warning_enabled = true;
};

// Partial configuration update received via MQTT
struct ConfigUpdatePatch {
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
    int wifi_rssi = 0;
    char ip_address[16] = "0.0.0.0";
    uint32_t last_db_sync = 0;
};

#endif // TYPES_H

