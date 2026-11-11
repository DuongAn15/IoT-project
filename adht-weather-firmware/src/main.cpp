#include <Arduino.h>
#include <esp_idf_version.h>
#include <esp_task_wdt.h>
#include "config.h"
#include "types.h"
#include "sensors/sensor_manager.h"
#include "network/wifi_manager.h"
#include "network/mqtt_manager.h"
#include "display/oled_manager.h"
#include "storage/storage_manager.h"

// Shared system state protected by stateMux across FreeRTOS cores
portMUX_TYPE stateMux = portMUX_INITIALIZER_UNLOCKED;
SystemConfig sysConfig;
char currentAlertMsg[32] = "";

// Non-blocking remote control flags (written on Core 0, executed on Core 1 / taskNetwork)
bool manualBuzzerActive = false;
uint32_t manualBuzzerStartMs = 0;
uint32_t manualBuzzerDurationMs = 0;

bool manualLedOverride = false;
bool manualLedState = false;

bool pendingReboot = false;
uint32_t pendingRebootRequestedMs = 0;

// Task handles
TaskHandle_t taskSensorsHandle = NULL;
TaskHandle_t taskNetworkHandle = NULL;
TaskHandle_t taskDisplayHandle = NULL;
TaskHandle_t taskAlertHandle = NULL;

static void configureWatchdog() {
#if ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 0, 0)
    esp_task_wdt_config_t twdtConfig = {
        .timeout_ms = WDT_TIMEOUT_MS,
        .idle_core_mask = (1 << 0),
        .trigger_panic = true,
    };
    esp_err_t err = esp_task_wdt_reconfigure(&twdtConfig);
    if (err == ESP_ERR_INVALID_STATE) {
        err = esp_task_wdt_init(&twdtConfig);
    }
    Serial.printf("[WDT] Configured %d ms timeout (err=%d)\n", WDT_TIMEOUT_MS, static_cast<int>(err));
#else
    esp_err_t err = esp_task_wdt_init(WDT_TIMEOUT_MS / 1000, true);
    Serial.printf("[WDT] Configured %d s timeout (err=%d)\n", WDT_TIMEOUT_MS / 1000, static_cast<int>(err));
#endif
}

// Callback: Handle MQTT Commands from Mobile App (Non-blocking, Core 0)
void handleMqttCommand(const String &cmd, const String &arg) {
    Serial.printf("[MAIN] Received Command: '%s' (arg: '%s')\n", cmd.c_str(), arg.c_str());

    if (cmd == "buzzer") {
        long parsed = arg.length() > 0 ? arg.toInt() : 300;
        uint32_t duration = (parsed > 0) ? static_cast<uint32_t>(parsed) : 300;
        if (duration < 50) duration = 50;
        if (duration > 10000) duration = 10000;

        portENTER_CRITICAL(&stateMux);
        manualBuzzerActive = true;
        manualBuzzerStartMs = millis();
        manualBuzzerDurationMs = duration;
        portEXIT_CRITICAL(&stateMux);

        Serial.printf("[COMMAND] Scheduled non-blocking BUZZER for %lu ms\n", static_cast<unsigned long>(duration));
    } else if (cmd == "led") {
        bool targetState = false;
        bool overrideActive = true;

        portENTER_CRITICAL(&stateMux);
        if (arg.equalsIgnoreCase("on") || arg.equalsIgnoreCase("true")) {
            targetState = true;
        } else if (arg == "0" || arg.equalsIgnoreCase("off") || arg.equalsIgnoreCase("false")) {
            targetState = false;
        } else if (arg.equalsIgnoreCase("auto")) {
            overrideActive = false;
            targetState = false;
        } else {
            // Bao gồm arg == "" và arg == "1" từ nút đơn trên Flutter App -> Đảo trạng thái
            targetState = !manualLedState;
        }
        manualLedOverride = overrideActive;
        manualLedState = targetState;
        portEXIT_CRITICAL(&stateMux);

        Serial.printf("[COMMAND] LED mode=%s state=%s\n",
                      overrideActive ? "MANUAL" : "AUTO",
                      targetState ? "ON" : "OFF");
    } else if (cmd == "reset" || cmd == "reboot") {
        portENTER_CRITICAL(&stateMux);
        pendingReboot = true;
        pendingRebootRequestedMs = millis();
        portEXIT_CRITICAL(&stateMux);

        Serial.println("[COMMAND] Reboot scheduled in 500ms via MQTT!");
    } else if (cmd == "reset_rain") {
        sensorMgr.resetRainTotal();
        Serial.println("[COMMAND] Reset rain_total and rain_rate to 0.0 mm");
    } else {
        Serial.printf("[COMMAND] Unknown command: '%s'\n", cmd.c_str());
    }
}

// Callback: Handle MQTT Partial Config Updates from Mobile App (Core 0)
void handleMqttConfig(const ConfigUpdatePatch &patch) {
    SystemConfig merged;

    portENTER_CRITICAL(&stateMux);
    merged = sysConfig;
    if (patch.has_temp_max) merged.temp_max_alert = patch.temp_max;
    if (patch.has_temp_min) merged.temp_min_alert = patch.temp_min;
    if (patch.has_humi_max) merged.humi_max_alert = patch.humi_max;
    if (patch.has_wind_max) merged.wind_max_alert = patch.wind_max;
    if (patch.has_rain_max) merged.rain_max_alert = patch.rain_max;
    if (patch.has_auto_warning) merged.auto_warning_enabled = patch.auto_warning;
    if (patch.has_buzzer) merged.buzzer_enabled = patch.buzzer;
    sysConfig = merged;
    portEXIT_CRITICAL(&stateMux);

    Serial.println("[MAIN] Received Config update via MQTT! Active thresholds:");
    Serial.printf("  • Temp Max: %.1f °C, Temp Min: %.1f °C\n", merged.temp_max_alert, merged.temp_min_alert);
    Serial.printf("  • Humi Max: %.1f %%\n", merged.humi_max_alert);
    Serial.printf("  • Wind Max: %.1f m/s, Rain Max: %.1f mm/h\n", merged.wind_max_alert, merged.rain_max_alert);
    Serial.printf("  • Auto Warning: %s, Buzzer Enabled: %s\n",
                  merged.auto_warning_enabled ? "TRUE" : "FALSE",
                  merged.buzzer_enabled ? "TRUE" : "FALSE");

    storageMgr.saveConfig(merged);
    Serial.println("[MAIN] Successfully saved merged config to NVS Flash!");
}

// ----------------------------------------------------------------
// TASK 1: Sensor Reading (DHT11, Rain, Wind) - Core 1
// ----------------------------------------------------------------
void taskSensors(void *pvParameters) {
    esp_task_wdt_add(NULL);

    while (1) {
        esp_task_wdt_reset();
        sensorMgr.update();
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}

// ----------------------------------------------------------------
// TASK 2: Network & Cloud (WiFi, MQTT Pub/Sub) - Core 0
// ----------------------------------------------------------------
void taskNetwork(void *pvParameters) {
    esp_task_wdt_add(NULL);
    uint32_t lastMqttPub = 0;

    while (1) {
        esp_task_wdt_reset();
        wifiMgr.loop();
        mqttMgr.loop();
        esp_task_wdt_reset();

        uint32_t now = millis();

        // Execute deferred reboot cleanly after MQTT loop drains
        bool doReboot = false;
        portENTER_CRITICAL(&stateMux);
        if (pendingReboot && static_cast<uint32_t>(now - pendingRebootRequestedMs) >= 500) {
            doReboot = true;
        }
        portEXIT_CRITICAL(&stateMux);

        if (doReboot) {
            Serial.println("[COMMAND] Restarting ESP32 now...");
            Serial.flush();
            ESP.restart();
        }

        // Publish Realtime Telemetry via MQTT every 5s (keep Backend contract unchanged)
        if (static_cast<uint32_t>(now - lastMqttPub) >= MQTT_PUBLISH_INTERVAL_MS) {
            lastMqttPub = now;
            if (mqttMgr.isConnected()) {
                WeatherData weather = sensorMgr.getData();
                NetworkStatus net = wifiMgr.getStatus();
                mqttMgr.publishTelemetry(weather, net.wifi_rssi);
            }
        }

        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

// ----------------------------------------------------------------
// TASK 3: OLED Display Refresh - Core 1
// ----------------------------------------------------------------
void taskDisplay(void *pvParameters) {
    char alertBuf[32];

    while (1) {
        WeatherData weather = sensorMgr.getData();
        NetworkStatus net = wifiMgr.getStatus();
        net.mqtt_connected = mqttMgr.isConnected();

        portENTER_CRITICAL(&stateMux);
        snprintf(alertBuf, sizeof(alertBuf), "%s", currentAlertMsg);
        portEXIT_CRITICAL(&stateMux);

        oledMgr.update(weather, net, alertBuf);
        vTaskDelay(pdMS_TO_TICKS(DISPLAY_UPDATE_MS));
    }
}

// ----------------------------------------------------------------
// TASK 4: Alert Monitor & Single Hardware GPIO Owner (Buzzer & LED) - Core 1
// ----------------------------------------------------------------
void taskAlert(void *pvParameters) {
    bool alarmPulseOn = false;
    uint32_t lastPulseToggleMs = millis();

    while (1) {
        uint32_t now = millis();
        WeatherData weather = sensorMgr.getData();

        SystemConfig cfg;
        bool bActive = false;
        uint32_t bStart = 0;
        uint32_t bDuration = 0;
        bool ledOverride = false;
        bool ledManualState = false;

        portENTER_CRITICAL(&stateMux);
        cfg = sysConfig;
        bActive = manualBuzzerActive;
        bStart = manualBuzzerStartMs;
        bDuration = manualBuzzerDurationMs;
        ledOverride = manualLedOverride;
        ledManualState = manualLedState;
        portEXIT_CRITICAL(&stateMux);

        bool buzzerManualOn = false;
        if (bActive) {
            if (static_cast<uint32_t>(now - bStart) < bDuration) {
                buzzerManualOn = true;
            } else {
                portENTER_CRITICAL(&stateMux);
                if (manualBuzzerStartMs == bStart) {
                    manualBuzzerActive = false;
                }
                portEXIT_CRITICAL(&stateMux);
            }
        }

        char nextAlertMsg[32] = "";
        bool triggerAlarm = false;

        if (cfg.auto_warning_enabled) {
            if (weather.has_valid_dht && weather.dht_ok && weather.temperature >= cfg.temp_max_alert) {
                snprintf(nextAlertMsg, sizeof(nextAlertMsg), "HIGH TEMP!");
                triggerAlarm = true;
            } else if (weather.has_valid_dht && weather.dht_ok && weather.temperature <= cfg.temp_min_alert) {
                snprintf(nextAlertMsg, sizeof(nextAlertMsg), "LOW TEMP!");
                triggerAlarm = true;
            } else if (weather.wind_speed >= cfg.wind_max_alert) {
                snprintf(nextAlertMsg, sizeof(nextAlertMsg), "STRONG WIND!");
                triggerAlarm = true;
            } else if (weather.rain_rate >= cfg.rain_max_alert) {
                snprintf(nextAlertMsg, sizeof(nextAlertMsg), "HEAVY RAIN!");
                triggerAlarm = true;
            } else if (weather.has_valid_dht && weather.dht_ok && weather.humidity >= cfg.humi_max_alert) {
                snprintf(nextAlertMsg, sizeof(nextAlertMsg), "HIGH HUMI!");
                triggerAlarm = true;
            }
        }

        portENTER_CRITICAL(&stateMux);
        snprintf(currentAlertMsg, sizeof(currentAlertMsg), "%s", nextAlertMsg);
        portEXIT_CRITICAL(&stateMux);

        if (triggerAlarm) {
            uint32_t phaseDuration = alarmPulseOn ? 150 : 350;
            if (static_cast<uint32_t>(now - lastPulseToggleMs) >= phaseDuration) {
                alarmPulseOn = !alarmPulseOn;
                lastPulseToggleMs = now;
            }
        } else {
            alarmPulseOn = false;
            lastPulseToggleMs = now;
        }

        bool buzzerOut = buzzerManualOn || (triggerAlarm && cfg.buzzer_enabled && alarmPulseOn);
        bool ledOut = triggerAlarm ? alarmPulseOn : (ledOverride ? ledManualState : false);

        digitalWrite(PIN_BUZZER, buzzerOut ? HIGH : LOW);
        digitalWrite(PIN_LED, ledOut ? LED_ON_LEVEL : LED_OFF_LEVEL);

        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

// ================================================================
// SETUP & MAIN
// ================================================================
void setup() {
    Serial.begin(115200);
    Serial.println("\n=================================");
    Serial.println("  ADHT WEATHER STATION SYSTEM V2 ");
    Serial.println("  MQTT + GATEWAY + FREERTOS      ");
    Serial.println("=================================");

    // 1. Initialize GPIO pins (LED Active-LOW, Buzzer Active-HIGH)
    digitalWrite(PIN_LED, LED_OFF_LEVEL);
    digitalWrite(PIN_BUZZER, LOW);
    pinMode(PIN_LED, OUTPUT);
    pinMode(PIN_BUZZER, OUTPUT);
    digitalWrite(PIN_LED, LED_OFF_LEVEL);
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

    // 5. Initialize Network (WiFi, MQTT)
    oledMgr.showBootScreen("Connecting WiFi...");
    wifiMgr.begin();

    mqttMgr.setCommandCallback(handleMqttCommand);
    mqttMgr.setConfigCallback(handleMqttConfig);
    mqttMgr.begin();

    oledMgr.showBootScreen("System Ready!");
    delay(1000);

    // 6. Configure Watchdog & Create FreeRTOS Tasks
    configureWatchdog();
    xTaskCreatePinnedToCore(taskSensors, "SensorsTask", 1024 * 4,  NULL, 3, &taskSensorsHandle, 1);
    xTaskCreatePinnedToCore(taskNetwork, "NetworkTask", 1024 * 10, NULL, 2, &taskNetworkHandle, 0);
    xTaskCreatePinnedToCore(taskDisplay, "DisplayTask", 1024 * 4,  NULL, 1, &taskDisplayHandle, 1);
    xTaskCreatePinnedToCore(taskAlert,   "AlertTask",   1024 * 4,  NULL, 1, &taskAlertHandle,   1);
}

void loop() {
    vTaskDelay(pdMS_TO_TICKS(1000));
}
