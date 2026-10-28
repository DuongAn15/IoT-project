#include <Arduino.h>
#include "config.h"
#include "types.h"
#include "sensors/sensor_manager.h"
#include "network/wifi_manager.h"
#include "network/mqtt_manager.h"
#include "display/oled_manager.h"
#include "storage/storage_manager.h"

// System state
SystemConfig sysConfig;
String currentAlertMsg = "";
bool manualBuzzer = false;

// Task handles
TaskHandle_t taskSensorsHandle = NULL;
TaskHandle_t taskNetworkHandle = NULL;
TaskHandle_t taskDisplayHandle = NULL;
TaskHandle_t taskAlertHandle = NULL;

// Callback: Handle MQTT Commands from Mobile App
void handleMqttCommand(const String &cmd, const String &arg) {
    Serial.printf("[MAIN] Received Command: %s (arg: %s)\n", cmd.c_str(), arg.c_str());
    if (cmd == "buzzer") {
        digitalWrite(PIN_BUZZER, HIGH);
        delay(arg.toInt() > 0 ? arg.toInt() : 300);
        digitalWrite(PIN_BUZZER, LOW);
    } else if (cmd == "led") {
        digitalWrite(PIN_LED, !digitalRead(PIN_LED));
    } else if (cmd == "reset") {
        Serial.println("[MAIN] Reboot requested via MQTT!");
        ESP.restart();
    }
}

// Callback: Handle MQTT Config Updates from Mobile App
void handleMqttConfig(const SystemConfig &newCfg) {
    Serial.println("[MAIN] Received Config update via MQTT!");
    sysConfig = newCfg;
    storageMgr.saveConfig(sysConfig);
}

// ----------------------------------------------------------------
// TASK 1: Sensor Reading (DHT11, Rain, Wind)
// ----------------------------------------------------------------
void taskSensors(void *pvParameters) {
    while (1) {
        sensorMgr.update();
        vTaskDelay(pdMS_TO_TICKS(100)); // 100ms
    }
}

// ----------------------------------------------------------------
// TASK 2: Network & Cloud (WiFi, MQTT Pub/Sub)
// ----------------------------------------------------------------
void taskNetwork(void *pvParameters) {
    uint32_t lastMqttPub = 0;

    while (1) {
        wifiMgr.loop();
        mqttMgr.loop();

        uint32_t now = millis();
        WeatherData weather = sensorMgr.getData();
        NetworkStatus net = wifiMgr.getStatus();

        // Publish Realtime Telemetry via MQTT (EMQX Cloud automatically forwards to Supabase)
        if (now - lastMqttPub >= MQTT_PUBLISH_INTERVAL_MS) {
            lastMqttPub = now;
            if (mqttMgr.isConnected()) {
                mqttMgr.publishTelemetry(weather, net.wifi_rssi);
            }
        }

        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

// ----------------------------------------------------------------
// TASK 3: OLED Display Refresh
// ----------------------------------------------------------------
void taskDisplay(void *pvParameters) {
    while (1) {
        WeatherData weather = sensorMgr.getData();
        NetworkStatus net = wifiMgr.getStatus();
        net.mqtt_connected = mqttMgr.isConnected();

        oledMgr.update(weather, net, currentAlertMsg);
        vTaskDelay(pdMS_TO_TICKS(DISPLAY_UPDATE_MS));
    }
}

// ----------------------------------------------------------------
// TASK 4: Alert Monitor (Buzzer & LED)
// ----------------------------------------------------------------
void taskAlert(void *pvParameters) {
    while (1) {
        WeatherData weather = sensorMgr.getData();
        currentAlertMsg = "";
        bool triggerAlarm = false;

        if (sysConfig.auto_warning_enabled) {
            if (weather.temperature >= sysConfig.temp_max_alert) {
                currentAlertMsg = "HIGH TEMP!";
                triggerAlarm = true;
            } else if (weather.wind_speed >= sysConfig.wind_max_alert) {
                currentAlertMsg = "STRONG WIND!";
                triggerAlarm = true;
            } else if (weather.rain_rate >= sysConfig.rain_max_alert) {
                currentAlertMsg = "HEAVY RAIN!";
                triggerAlarm = true;
            }
        }

        if (triggerAlarm && sysConfig.buzzer_enabled) {
            digitalWrite(PIN_BUZZER, HIGH);
            digitalWrite(PIN_LED, HIGH);
            vTaskDelay(pdMS_TO_TICKS(150));
            digitalWrite(PIN_BUZZER, LOW);
            digitalWrite(PIN_LED, LOW);
            vTaskDelay(pdMS_TO_TICKS(350));
        } else {
            digitalWrite(PIN_BUZZER, LOW);
            vTaskDelay(pdMS_TO_TICKS(500));
        }
    }
}

// ================================================================
// SETUP & MAIN
// ================================================================
void setup() {
    Serial.begin(115200);
    Serial.println("\n=================================");
    Serial.println("  ADHT WEATHER STATION SYSTEM V2 ");
    Serial.println("  MQTT + SUPABASE + FREERTOS     ");
    Serial.println("=================================");

    // 1. Initialize GPIO pins
    pinMode(PIN_LED, OUTPUT);
    pinMode(PIN_BUZZER, OUTPUT);
    digitalWrite(PIN_LED, LOW);
    digitalWrite(PIN_BUZZER, LOW);

    // 2. Initialize OLED
    oledMgr.begin();
    oledMgr.showBootScreen("Initializing...");

    // 3. Initialize Storage & Load Config
    storageMgr.begin();
    storageMgr.loadConfig(sysConfig);

    // 4. Initialize Sensors
    oledMgr.showBootScreen("Init Sensors...");
    sensorMgr.begin();

    // 5. Initialize Network (WiFi, MQTT, Supabase)
    oledMgr.showBootScreen("Connecting WiFi...");
    wifiMgr.begin();

    mqttMgr.setCommandCallback(handleMqttCommand);
    mqttMgr.setConfigCallback(handleMqttConfig);
    mqttMgr.begin();

    oledMgr.showBootScreen("System Ready!");
    delay(1000);

    // 6. Create FreeRTOS Tasks
    xTaskCreatePinnedToCore(taskSensors, "SensorsTask", 1024 * 4, NULL, 3, &taskSensorsHandle, 1);
    xTaskCreatePinnedToCore(taskNetwork, "NetworkTask", 1024 * 10, NULL, 2, &taskNetworkHandle, 0);
    xTaskCreatePinnedToCore(taskDisplay, "DisplayTask", 1024 * 4, NULL, 1, &taskDisplayHandle, 1);
    xTaskCreatePinnedToCore(taskAlert,   "AlertTask",   1024 * 4, NULL, 1, &taskAlertHandle,   1);
}

void loop() {
    vTaskDelay(pdMS_TO_TICKS(1000));
}
