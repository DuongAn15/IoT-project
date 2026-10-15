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
};

// Alert and Threshold configuration
struct SystemConfig {
    float temp_max_alert = 38.0f;  // Alert when temp > threshold
    float temp_min_alert = 10.0f;  // Alert when temp < threshold
    float humi_max_alert = 90.0f;  // Alert when humi > threshold
    float wind_max_alert = 15.0f;  // Alert when wind > 15 m/s (strong wind)
    float rain_max_alert = 50.0f;  // Alert when rain > 50 mm/h (heavy storm)
    bool buzzer_enabled = true;
    bool auto_warning_enabled = true;
};

// System network & connection status
struct NetworkStatus {
    bool wifi_connected = false;
    bool mqtt_connected = false;
    int wifi_rssi = 0;
    String ip_address = "0.0.0.0";
    uint32_t last_db_sync = 0;
};

#endif // TYPES_H

