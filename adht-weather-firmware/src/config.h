#ifndef CONFIG_H
#define CONFIG_H

#include <Arduino.h>

// ==========================================
// 1. HARDWARE PINOUTS
// ==========================================
#define PIN_DHT11         26    // DHT11 Sensor
#define PIN_RAIN_SENSOR   15    // Rain tipping bucket (Interrupt)
#define PIN_WIND_SENSOR   13    // Anemometer pulse (Interrupt)

#define PIN_OLED_SDA      21    // I2C OLED SDA
#define PIN_OLED_SCL      22    // I2C OLED SCL
#define OLED_I2C_ADDR     0x3C  // OLED SH1106 / SSD1306 128x64

#define PIN_LED           33    // Status LED
#define PIN_BUZZER        2     // Alert Buzzer

#define PIN_BTN_SET       32    // Button SET
#define PIN_BTN_UP        35    // Button UP
#define PIN_BTN_DOWN      34    // Button DOWN

// ==========================================
// 2. SENSOR MECHANICAL SPECS
// ==========================================
// Rain Gauge: Phễu bán kính 55mm (S=9498 mm2), mỗi lần bập bênh lật là 6ml
#define RAIN_FUNNEL_AREA_MM2    9498.0f
#define RAIN_BUCKET_ML          6.0f
#define RAIN_SAMPLE_PERIOD_SEC  60       // Chu kỳ tính lượng mưa (giây)

// Anemometer: Trục cánh quạt đường kính 208mm = 0.208m
#define WIND_ANEMOMETER_D_MM    208.0f   // mm
#define WIND_SAMPLE_PERIOD_SEC  5        // Chu kỳ tính tốc độ gió (giây)

// ==========================================
// 3. WIFI CREDENTIALS (Load từ .env)
// ==========================================
#ifndef DEFAULT_WIFI_SSID
#define DEFAULT_WIFI_SSID       "Your_WiFi_SSID"
#endif

#ifndef DEFAULT_WIFI_PASS
#define DEFAULT_WIFI_PASS       "Your_WiFi_Password"
#endif

// ==========================================
// 4. EMQX CLOUD (MQTT BROKER) (Load từ .env)
// ==========================================
#ifndef MQTT_BROKER_HOST
#define MQTT_BROKER_HOST        "xxxxxxxx.ala.asia-southeast1.emqxsl.com"
#endif

#ifndef MQTT_BROKER_PORT
#define MQTT_BROKER_PORT        8883     // TLS/SSL Port
#endif

#ifndef MQTT_USERNAME
#define MQTT_USERNAME           "adht_device"
#endif

#ifndef MQTT_PASSWORD
#define MQTT_PASSWORD           "Your_Mqtt_Password"
#endif

#ifndef DEVICE_ID
#define DEVICE_ID               "adht_weather_01"
#endif

// MQTT Topics
#define TOPIC_TELEMETRY         "adht/weather/telemetry"
#define TOPIC_STATUS            "adht/weather/status"
#define TOPIC_COMMAND           "adht/weather/command"
#define TOPIC_CONFIG            "adht/weather/config"

// ==========================================
// 5. TIMING INTERVALS
// ==========================================
#define SENSOR_READ_INTERVAL_MS 2000     // 2 giây đọc cảm biến 1 lần
#define MQTT_PUBLISH_INTERVAL_MS 3000    // 3 giây publish MQTT 1 lần (EMQX tự forward sang Supabase)
#define DISPLAY_UPDATE_MS       500      // 500ms cập nhật màn hình OLED

#endif // CONFIG_H
