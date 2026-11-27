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

// Alarm Snooze (activated via SET button long-press or remote command)
uint32_t alarmSnoozedUntilMs = 0;

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

static constexpr size_t CMD_DEDUP_CAPACITY = 16;
static char recentCmdRequestIds[CMD_DEDUP_CAPACITY][65] = {{0}};
static size_t recentCmdHead = 0;

static bool isDuplicateCommandRequest(const String &requestId) {
    if (requestId.length() == 0) return false;
    for (size_t i = 0; i < CMD_DEDUP_CAPACITY; ++i) {
        if (recentCmdRequestIds[i][0] != '\0' && requestId.equals(recentCmdRequestIds[i])) {
            return true;
        }
    }
    return false;
}

static void recordCommandRequest(const String &requestId) {
    if (requestId.length() == 0) return;
    snprintf(recentCmdRequestIds[recentCmdHead], sizeof(recentCmdRequestIds[0]), "%s", requestId.c_str());
    recentCmdHead = (recentCmdHead + 1) % CMD_DEDUP_CAPACITY;
}

static bool isIsoExpired(const char *expiresAt) {
    if (!expiresAt || expiresAt[0] == '\0') return false;
    time_t nowEpoch = time(nullptr);
    if (nowEpoch < 1700000000L) return false; // SNTP unsynchronized -> do not drop valid commands
    struct tm tmExp = {};
    if (sscanf(expiresAt, "%d-%d-%dT%d:%d:%d",
               &tmExp.tm_year, &tmExp.tm_mon, &tmExp.tm_mday,
               &tmExp.tm_hour, &tmExp.tm_min, &tmExp.tm_sec) != 6) {
        return false;
    }
    tmExp.tm_year -= 1900;
    tmExp.tm_mon -= 1;
    // mktime uses local TZ; compute UTC epoch viasetenv/timegm fallback or TZ=UTC
    setenv("TZ", "UTC0", 1);
    tzset();
    time_t expEpoch = mktime(&tmExp);
    return expEpoch > 0 && nowEpoch > expEpoch;
}

// Callback: Handle MQTT Commands from Mobile App (Non-blocking, Core 0)
void handleMqttCommand(const String &cmd, const String &arg, const String &requestId, const String &expiresAt) {
    Serial.printf("[MAIN] Received Command: '%s' (arg: '%s', req: '%s')\n",
                  cmd.c_str(), arg.c_str(), requestId.c_str());

    if (isIsoExpired(expiresAt.c_str())) {
        mqttMgr.publishOperationAck(requestId.c_str(), "command", "failed", 0, "expired", "Command expired before execution");
        return;
    }
    if (isDuplicateCommandRequest(requestId)) {
        Serial.printf("[COMMAND] Duplicate request_id '%s' ignored (idempotent)\n", requestId.c_str());
        mqttMgr.publishOperationAck(requestId.c_str(), "command", "applied");
        return;
    }

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
        mqttMgr.publishOperationAck(requestId.c_str(), "command", "rejected", 0, "unknown_command", "Unsupported command");
        return;
    }
    recordCommandRequest(requestId);
    mqttMgr.publishOperationAck(requestId.c_str(), "command", "applied");
}

// Callback: Handle MQTT Partial Config Updates from Mobile App (Core 0)
void handleMqttConfig(const ConfigUpdatePatch &patch) {
    if (isIsoExpired(patch.expires_at)) {
        mqttMgr.publishOperationAck(patch.request_id, "config", "failed", patch.version, "expired", "Config update expired");
        return;
    }

    SystemConfig merged;
    portENTER_CRITICAL(&stateMux);
    merged = sysConfig;
    portEXIT_CRITICAL(&stateMux);

    if (patch.has_version && patch.version < merged.version) {
        mqttMgr.publishOperationAck(patch.request_id, "config", "rejected", merged.version, "stale_version", "Version is older than active config");
        return;
    }
    if (patch.has_version && patch.version == merged.version) {
        mqttMgr.publishOperationAck(patch.request_id, "config", "applied", merged.version);
        return;
    }

    if (patch.has_temp_max) merged.temp_max_alert = patch.temp_max;
    if (patch.has_temp_min) merged.temp_min_alert = patch.temp_min;
    if (patch.has_humi_max) merged.humi_max_alert = patch.humi_max;
    if (patch.has_wind_max) merged.wind_max_alert = patch.wind_max;
    if (patch.has_rain_max) merged.rain_max_alert = patch.rain_max;
    if (patch.has_auto_warning) merged.auto_warning_enabled = patch.auto_warning;
    if (patch.has_buzzer) merged.buzzer_enabled = patch.buzzer;
    if (patch.has_version) merged.version = patch.version;

    // Validate domain after partial merge before persisting or applying
    if (merged.temp_min_alert >= merged.temp_max_alert ||
        merged.temp_min_alert < -40.0f || merged.temp_max_alert > 80.0f ||
        merged.humi_max_alert < 0.0f || merged.humi_max_alert > 100.0f ||
        merged.wind_max_alert < 0.0f || merged.wind_max_alert > 100.0f ||
        merged.rain_max_alert < 0.0f || merged.rain_max_alert > 500.0f) {
        mqttMgr.publishOperationAck(patch.request_id, "config", "rejected", merged.version, "invalid_domain", "Config failed post-merge validation");
        return;
    }

    // Persist with read-back verification BEFORE applying in RAM or ACKing
    if (!storageMgr.saveConfig(merged)) {
        Serial.println("[MAIN] ERROR: NVS saveConfig failed; keeping previous config!");
        mqttMgr.publishOperationAck(patch.request_id, "config", "failed", merged.version, "nvs_write_failed", "NVS persistence verification failed");
        return;
    }

    portENTER_CRITICAL(&stateMux);
    sysConfig = merged;
    portEXIT_CRITICAL(&stateMux);

    Serial.printf("[MAIN] Applied & persisted Config v%lu via MQTT!\n",
                  static_cast<unsigned long>(merged.version));
    mqttMgr.publishOperationAck(patch.request_id, "config", "applied", merged.version);
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

#if ENABLE_V2_MINUTE_LOG_PUBLISHER
        MinuteLogSample minuteLog;
        if (sensorMgr.takePendingMinuteLog(minuteLog)) {
            mqttMgr.publishMinuteLog(minuteLog);
        }
#endif

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
// TASK 4: Alert Monitor, Hardware Buttons & Single GPIO Owner - Core 1
// ----------------------------------------------------------------
void taskAlert(void *pvParameters) {
    bool alarmPulseOn = false;
    uint32_t lastPulseToggleMs = millis();

    // Button debounce & hold state variables
    int lastRawSetPin = HIGH;
    uint32_t setPressStartMs = 0;
    bool setProvisionHintShown = false;

    bool snoozeActive = false;
    uint32_t snoozeStartMs = 0;

#if ENABLE_EXTERNAL_BUTTONS_UP_DOWN
    int lastRawUpPin = HIGH;
    uint32_t upLastEdgeMs = 0;
    bool upStableLow = false;

    int lastRawDownPin = HIGH;
    uint32_t downLastEdgeMs = 0;
    bool downStableLow = false;
#endif

    while (1) {
        uint32_t now = millis();

        // 1. Scan Hardware Button SET (GPIO 32, Active-LOW with internal INPUT_PULLUP)
        //    - Tap (<2s): wake OLED
        //    - Hold 2..8s & release: snooze buzzer for 5 minutes
        //    - Hold >=8s & release: trigger Wi-Fi provisioning portal
        int rawSet = digitalRead(PIN_BTN_SET);
        if (rawSet == LOW) {
            if (lastRawSetPin == HIGH) {
                setPressStartMs = now;
                setProvisionHintShown = false;
                oledMgr.wakeScreen();
            } else if (!setProvisionHintShown &&
                       static_cast<uint32_t>(now - setPressStartMs) >= BTN_PROVISION_PRESS_MS) {
                setProvisionHintShown = true;
                oledMgr.wakeScreen();
                portENTER_CRITICAL(&stateMux);
                manualBuzzerActive = true;
                manualBuzzerStartMs = now;
                manualBuzzerDurationMs = 80;
                portEXIT_CRITICAL(&stateMux);
                Serial.println("[BUTTON] SET >=8s held: release to enter Wi-Fi provisioning portal");
            }
        } else if (lastRawSetPin == LOW) {
            uint32_t heldMs = static_cast<uint32_t>(now - setPressStartMs);
            if (heldMs >= BTN_PROVISION_PRESS_MS) {
                Serial.println("[BUTTON] SET released >=8s: requesting Wi-Fi provisioning portal");
                wifiMgr.requestProvisioningPortal();
            } else if (heldMs >= BTN_LONG_PRESS_MS) {
                snoozeActive = true;
                snoozeStartMs = now;
                portENTER_CRITICAL(&stateMux);
                manualBuzzerActive = true;
                manualBuzzerStartMs = now;
                manualBuzzerDurationMs = 100;
                portEXIT_CRITICAL(&stateMux);
                Serial.println("[BUTTON] SET 2-8s release: Alarm buzzer snoozed for 5 minutes!");
            } else if (heldMs >= BTN_DEBOUNCE_MS) {
                oledMgr.wakeScreen();
                Serial.println("[BUTTON] SET tap: OLED woken");
            }
            setProvisionHintShown = false;
        }
        lastRawSetPin = rawSet;

#if ENABLE_EXTERNAL_BUTTONS_UP_DOWN
        // 1b. UP (GPIO 35) & DOWN (GPIO 34) - Active-LOW with external pull-up (INPUT only)
        int rawUp = digitalRead(PIN_BTN_UP);
        if (rawUp != lastRawUpPin) {
            upLastEdgeMs = now;
            lastRawUpPin = rawUp;
        } else if (static_cast<uint32_t>(now - upLastEdgeMs) >= BTN_DEBOUNCE_MS) {
            bool isLow = (rawUp == LOW);
            if (isLow && !upStableLow) {
                oledMgr.nextPageClamped();
                Serial.printf("[BUTTON] UP: Page %u/3\n", oledMgr.getPage() + 1);
            }
            upStableLow = isLow;
        }

        int rawDown = digitalRead(PIN_BTN_DOWN);
        if (rawDown != lastRawDownPin) {
            downLastEdgeMs = now;
            lastRawDownPin = rawDown;
        } else if (static_cast<uint32_t>(now - downLastEdgeMs) >= BTN_DEBOUNCE_MS) {
            bool isLow = (rawDown == LOW);
            if (isLow && !downStableLow) {
                oledMgr.prevPage();
                Serial.printf("[BUTTON] DOWN: Page %u/3\n", oledMgr.getPage() + 1);
            }
            downStableLow = isLow;
        }
#endif

        // 2. Alert Monitoring & Threshold Checking
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

        if (setProvisionHintShown) {
            snprintf(nextAlertMsg, sizeof(nextAlertMsg), "RELEASE FOR WIFI");
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

        // Alarm Snooze check (wrap-safe): suppress buzzer while snoozed
        if (snoozeActive && static_cast<uint32_t>(now - snoozeStartMs) >= ALARM_SNOOZE_DURATION_MS) {
            snoozeActive = false;
        }
        bool isAlarmSnoozed = snoozeActive;
        bool buzzerOut = buzzerManualOn || (triggerAlarm && cfg.buzzer_enabled && alarmPulseOn && !isAlarmSnoozed);
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

    // 1. Initialize GPIO pins (LED Active-LOW, Buzzer Active-HIGH, Button SET with INPUT_PULLUP)
    digitalWrite(PIN_LED, LED_OFF_LEVEL);
    digitalWrite(PIN_BUZZER, LOW);
    pinMode(PIN_LED, OUTPUT);
    pinMode(PIN_BUZZER, OUTPUT);
    digitalWrite(PIN_LED, LED_OFF_LEVEL);
    digitalWrite(PIN_BUZZER, LOW);

    // Button SET uses internal pull-up (safe on GPIO 32)
    pinMode(PIN_BTN_SET, INPUT_PULLUP);

#if ENABLE_EXTERNAL_BUTTONS_UP_DOWN
    // GPIO 34 & 35 do NOT have internal pull-ups on ESP32; require external pull-up resistors
    pinMode(PIN_BTN_UP, INPUT);
    pinMode(PIN_BTN_DOWN, INPUT);
#endif

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
