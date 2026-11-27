#include "mqtt_manager.h"
#include "mqtt_ca_cert.h"
#include "../storage/storage_manager.h"
#include <ArduinoJson.h>
#include <esp_system.h>
#include <time.h>

MqttManager mqttMgr;

void MqttManager::staticCallback(char *topic, byte *payload, unsigned int length) {
    mqttMgr.onMessageReceived(topic, payload, length);
}

MqttManager::MqttManager() 
    : mqttClient(secureClient),
      lastReconnectAttempt(0),
      onCommand(nullptr),
      onConfig(nullptr),
      telemetrySequence(0),
      backlogHead(0),
      backlogCount(0)
{
    memset(bootId, 0, sizeof(bootId));
    memset(backlog, 0, sizeof(backlog));
}

void MqttManager::begin() {
    uint32_t r1 = esp_random();
    uint32_t r2 = esp_random();
    snprintf(bootId, sizeof(bootId), "%08lx%08lx",
             static_cast<unsigned long>(r1), static_cast<unsigned long>(r2));

    // Verify broker TLS certificate chain and hostname against embedded Root CAs
    secureClient.setCACert(MQTT_ROOT_CA);
    secureClient.setConnectionTimeout(5000);  // 5s TCP connect timeout
    secureClient.setHandshakeTimeout(10);     // 10s TLS handshake timeout

    mqttClient.setServer(MQTT_BROKER_HOST, MQTT_BROKER_PORT);
    mqttClient.setCallback(staticCallback);
    mqttClient.setBufferSize(1152);
    mqttClient.setSocketTimeout(5);           // 5s MQTT socket timeout
}

void MqttManager::setCommandCallback(CommandCallback cb) {
    onCommand = cb;
}

void MqttManager::setConfigCallback(ConfigUpdateCallback cb) {
    onConfig = cb;
}

bool MqttManager::reconnect() {
    if (WiFi.status() != WL_CONNECTED) {
        return false;
    }

    // X.509 certificate validity requires an accurate system clock via SNTP.
    if (time(nullptr) < 1700000000L) {
        Serial.println("[MQTT] Waiting for NTP time sync before TLS connect...");
        return false;
    }

    Serial.printf("[MQTT] Connecting to %s:%d...\n", MQTT_BROKER_HOST, MQTT_BROKER_PORT);

    // Last Will and Testament (LWT)
    char willPayload[64];
    snprintf(willPayload, sizeof(willPayload), "{\"status\":\"offline\",\"device\":\"%s\"}", DEVICE_ID);
    const char *willTopic = TOPIC_STATUS;
    int willQos = 1;
    bool willRetain = true;

    if (mqttClient.connect(DEVICE_ID, MQTT_USERNAME, MQTT_PASSWORD, 
                           willTopic, willQos, willRetain, willPayload)) {
        Serial.println("[MQTT] Connected successfully!");

        // Publish Online Status (Retained)
        char onlinePayload[128];
        snprintf(onlinePayload, sizeof(onlinePayload), 
                 "{\"status\":\"online\",\"device\":\"%s\",\"ip\":\"%s\"}",
                 DEVICE_ID, WiFi.localIP().toString().c_str());
        mqttClient.publish(TOPIC_STATUS, onlinePayload, true);
        Serial.printf("[MQTT] Published online status to [%s]: %s\n", TOPIC_STATUS, onlinePayload);

        // Subscribe to Command & Config topics (Chỉ subscribe topic định danh riêng của trạm)
        mqttClient.subscribe(TOPIC_COMMAND, 1);
        mqttClient.subscribe(TOPIC_CONFIG, 1);
        Serial.printf("[MQTT] Subscribed to device topics:\n  - %s\n  - %s\n", 
                      TOPIC_COMMAND, TOPIC_CONFIG);
        return true;
    } else {
        Serial.printf("[MQTT] Failed, state = %d\n", mqttClient.state());
        return false;
    }
}

void MqttManager::loop() {
    if (!mqttClient.connected()) {
        uint32_t now = millis();
        if (now - lastReconnectAttempt > 5000) {
            lastReconnectAttempt = now;
            if (reconnect()) {
                flushPendingAcks();
                flushBacklog();
            }
        }
    } else {
        mqttClient.loop();
        flushPendingAcks();
        flushBacklog();
    }
}

bool MqttManager::isConnected() {
    return mqttClient.connected();
}

void MqttManager::enqueueBacklog(const char *topic, const char *payload) {
    if (!topic || !payload || payload[0] == '\0') return;
    size_t writeIdx;
    if (backlogCount < TELEMETRY_BACKLOG_CAPACITY) {
        writeIdx = (backlogHead + backlogCount) % TELEMETRY_BACKLOG_CAPACITY;
        backlogCount++;
    } else {
        // Ring buffer full: overwrite oldest sample
        writeIdx = backlogHead;
        backlogHead = (backlogHead + 1) % TELEMETRY_BACKLOG_CAPACITY;
    }
    snprintf(backlog[writeIdx].topic, sizeof(backlog[writeIdx].topic), "%s", topic);
    snprintf(backlog[writeIdx].payload, TELEMETRY_PAYLOAD_MAX_BYTES, "%s", payload);
}

void MqttManager::flushBacklog() {
    size_t flushed = 0;
    while (backlogCount > 0 && mqttClient.connected() && flushed < 2) {
        if (!mqttClient.publish(backlog[backlogHead].topic, backlog[backlogHead].payload)) {
            break;
        }
        backlogHead = (backlogHead + 1) % TELEMETRY_BACKLOG_CAPACITY;
        backlogCount--;
        flushed++;
    }
}

void MqttManager::publishTelemetry(const WeatherData &data, int rssi) {
    telemetrySequence++;

    JsonDocument doc;
    doc["device_id"] = DEVICE_ID;
    doc["boot_id"] = bootId;
    doc["sequence"] = telemetrySequence;
    char sampleId[64];
    snprintf(sampleId, sizeof(sampleId), "%s:%s:%lu",
             DEVICE_ID, bootId, static_cast<unsigned long>(telemetrySequence));
    doc["sample_id"] = sampleId;
    doc["temp"] = round(data.temperature * 10.0f) / 10.0f;
    doc["humi"] = round(data.humidity * 10.0f) / 10.0f;
    doc["rain_rate"] = round(data.rain_rate * 100.0f) / 100.0f;
    doc["rain_total"] = round(data.rain_total * 100.0f) / 100.0f;
    doc["wind_speed"] = round(data.wind_speed * 10.0f) / 10.0f;
    doc["wind_max"] = round(data.wind_max * 10.0f) / 10.0f;
    doc["rssi"] = rssi;
    doc["uptime"] = millis() / 1000;

    char buffer[TELEMETRY_PAYLOAD_MAX_BYTES];
    serializeJson(doc, buffer, sizeof(buffer));

    if (!mqttClient.connected()) {
        enqueueBacklog(TOPIC_TELEMETRY, buffer);
        Serial.printf("[MQTT] Offline, queued telemetry seq=%lu (backlog=%u)\n",
                      static_cast<unsigned long>(telemetrySequence),
                      static_cast<unsigned int>(backlogCount));
        return;
    }

    // Publish duy nhất lên topic định danh riêng của trạm (TOPIC_TELEMETRY: adht/weather/{DEVICE_ID}/telemetry)
    bool ok = mqttClient.publish(TOPIC_TELEMETRY, buffer);
    if (ok) {
        Serial.printf("[MQTT] Published telemetry to [%s]: %s\n", TOPIC_TELEMETRY, buffer);
    } else {
        enqueueBacklog(TOPIC_TELEMETRY, buffer);
        Serial.println("[MQTT] Publish telemetry failed; queued to backlog!");
    }
}

static void formatIsoUtc(int64_t epochSec, char *out, size_t outSize) {
    time_t t = static_cast<time_t>(epochSec);
    struct tm tmUtc;
    gmtime_r(&t, &tmUtc);
    strftime(out, outSize, "%Y-%m-%dT%H:%M:%SZ", &tmUtc);
}

void MqttManager::publishMinuteLog(const MinuteLogSample &sample) {
    JsonDocument doc;
    doc["schema_version"] = 2;
    doc["type"] = "minute_log";
    doc["device_id"] = DEVICE_ID;
    doc["deployment_id"] = DEPLOYMENT_ID;
    doc["boot_id"] = bootId;
    doc["window_sequence"] = sample.window_sequence;

    if (sample.clock_synchronized) {
        doc["clock_quality"] = "synchronized";
        char startIso[24];
        char endIso[24];
        formatIsoUtc(sample.epoch_start_sec, startIso, sizeof(startIso));
        formatIsoUtc(sample.epoch_end_sec, endIso, sizeof(endIso));
        doc["interval_start"] = startIso;
        doc["interval_end"] = endIso;
    } else {
        doc["clock_quality"] = "unsynchronized";
        doc["uptime_start_ms"] = sample.uptime_start_ms;
        doc["uptime_end_ms"] = sample.uptime_end_ms;
    }

    JsonObject metrics = doc["metrics"].to<JsonObject>();
    if (sample.dht_valid_count > 0) {
        JsonObject temp = metrics["temperature"].to<JsonObject>();
        temp["unit"] = "degC";
        temp["sum"] = round(sample.temp_sum * 100.0f) / 100.0f;
        temp["count"] = sample.dht_valid_count;
        temp["min"] = round(sample.temp_min * 10.0f) / 10.0f;
        temp["max"] = round(sample.temp_max * 10.0f) / 10.0f;
        temp["latest"] = round(sample.temp_latest * 10.0f) / 10.0f;

        JsonObject humi = metrics["humidity"].to<JsonObject>();
        humi["unit"] = "percent_rh";
        humi["sum"] = round(sample.humi_sum * 100.0f) / 100.0f;
        humi["count"] = sample.dht_valid_count;
        humi["min"] = round(sample.humi_min * 10.0f) / 10.0f;
        humi["max"] = round(sample.humi_max * 10.0f) / 10.0f;
        humi["latest"] = round(sample.humi_latest * 10.0f) / 10.0f;
    }
    if (sample.wind_valid_count > 0) {
        JsonObject wind = metrics["wind_speed"].to<JsonObject>();
        wind["unit"] = "m/s";
        wind["sum"] = round(sample.wind_sum * 100.0f) / 100.0f;
        wind["count"] = sample.wind_valid_count;
        wind["min"] = round(sample.wind_min * 10.0f) / 10.0f;
        wind["max"] = round(sample.wind_max * 10.0f) / 10.0f;
        wind["latest"] = round(sample.wind_latest * 10.0f) / 10.0f;
    }

    JsonObject rain = doc["rain"].to<JsonObject>();
    char epochStr[36];
    snprintf(epochStr, sizeof(epochStr), "%s:reset-%lu",
             bootId, static_cast<unsigned long>(sample.rain_reset_epoch));
    rain["counter_epoch"] = epochStr;
    rain["calibration_version"] = RAIN_CALIBRATION_VERSION;
    rain["tip_count_start"] = sample.tip_count_start;
    rain["tip_count_end"] = sample.tip_count_end;

    JsonObject quality = doc["quality"].to<JsonObject>();
    uint32_t covMs = sample.uptime_end_ms - sample.uptime_start_ms;
    quality["dht_expected_count"] = sample.dht_expected_count;
    quality["dht_valid_count"] = sample.dht_valid_count;
    quality["wind_expected_count"] = sample.wind_expected_count;
    quality["wind_valid_count"] = sample.wind_valid_count;
    quality["coverage_ms"] = covMs;
    quality["rain_coverage_ms"] = covMs;

    char buffer[TELEMETRY_PAYLOAD_MAX_BYTES];
    size_t len = serializeJson(doc, buffer, sizeof(buffer));
    if (len >= sizeof(buffer) - 1) {
        Serial.println("[MQTT] v2 minute_log exceeded buffer size; dropped");
        return;
    }

    if (!mqttClient.connected() || !mqttClient.publish(TOPIC_TELEMETRY_LOG, buffer)) {
        enqueueBacklog(TOPIC_TELEMETRY_LOG, buffer);
        Serial.printf("[MQTT] Queued v2 minute_log seq=%lu\n",
                      static_cast<unsigned long>(sample.window_sequence));
    } else {
        Serial.printf("[MQTT] Published v2 minute_log seq=%lu\n",
                      static_cast<unsigned long>(sample.window_sequence));
    }
}

void MqttManager::flushPendingAcks() {
    if (!mqttClient.connected()) return;
    size_t sent = 0;
    for (size_t i = 0; i < StorageManager::ACK_SLOTS && sent < 2; ++i) {
        String payload = storageMgr.pendingAck(i);
        if (payload.isEmpty()) continue;
        if (!mqttClient.publish(TOPIC_ACK, payload.c_str())) break;
        storageMgr.clearPendingAck(i);
        sent++;
    }
}

void MqttManager::publishOperationAck(
    const char *requestId,
    const char *kind,
    const char *status,
    uint32_t version,
    const char *errorCode,
    const char *errorMessage) {
    if (!requestId || requestId[0] == '\0') return;

    JsonDocument doc;
    doc["request_id"] = requestId;
    doc["device_id"] = DEVICE_ID;
    doc["deployment_id"] = DEPLOYMENT_ID;
    doc["boot_id"] = bootId;
    doc["kind"] = kind;
    doc["status"] = status;
    if (version > 0) {
        doc["version"] = version;
    }
    if (errorCode && errorCode[0] != '\0') {
        doc["error_code"] = errorCode;
    }
    if (errorMessage && errorMessage[0] != '\0') {
        doc["error_message"] = errorMessage;
    }

    char buffer[384];
    serializeJson(doc, buffer, sizeof(buffer));
    if (!storageMgr.savePendingAck(String(buffer))) {
        // Do not silently drop an ACK if the persistent queue is full or NVS failed.
        Serial.println("[MQTT] ACK NVS queue full or write failed");
        if (mqttClient.connected() && !mqttClient.publish(TOPIC_ACK, buffer)) {
            enqueueBacklog(TOPIC_ACK, buffer);
        } else if (!mqttClient.connected()) {
            enqueueBacklog(TOPIC_ACK, buffer);
        }
        return;
    }
    flushPendingAcks();
}

void MqttManager::onMessageReceived(char *topic, byte *payload, unsigned int length) {
    if (!topic || !payload) {
        return;
    }
    Serial.printf("[MQTT] Received message on topic [%s]: %.*s\n",
                  topic, static_cast<int>(length), reinterpret_cast<const char *>(payload));

    // 1. Command handling (Chỉ nhận từ topic riêng của trạm: TOPIC_COMMAND)
    if (strcmp(topic, TOPIC_COMMAND) == 0) {
        JsonDocument doc;
        DeserializationError err = deserializeJson(doc, reinterpret_cast<const char *>(payload), length);
        if (err) {
            Serial.printf("[MQTT] JSON parse error for Command: %s\n", err.c_str());
            return;
        }

        String requestId = doc["request_id"] | "";
        String expiresAt = doc["expires_at"] | "";
        const char *depId = doc["deployment_id"] | "";
        if (depId[0] != '\0' && strcmp(depId, DEPLOYMENT_ID) != 0) {
            publishOperationAck(requestId.c_str(), "command", "rejected", 0, "deployment_mismatch", "Deployment ID mismatch");
            return;
        }

        String cmd = doc["cmd"] | "";
        String arg = "";
        if (doc["arg"].is<const char *>()) {
            arg = doc["arg"].as<const char *>();
        } else if (!doc["arg"].isNull()) {
            arg = doc["arg"].as<String>();
        }
        if (onCommand) {
            onCommand(cmd, arg, requestId, expiresAt);
        }
    }
    // 2. Config update handling (Chỉ nhận từ topic riêng của trạm: TOPIC_CONFIG)
    else if (strcmp(topic, TOPIC_CONFIG) == 0) {
        JsonDocument doc;
        DeserializationError err = deserializeJson(doc, reinterpret_cast<const char *>(payload), length);
        if (err) {
            Serial.printf("[MQTT] JSON parse error for Config: %s\n", err.c_str());
            return;
        }

        String requestId = doc["request_id"] | "";
        const char *depId = doc["deployment_id"] | "";
        if (depId[0] != '\0' && strcmp(depId, DEPLOYMENT_ID) != 0) {
            publishOperationAck(requestId.c_str(), "config", "rejected", 0, "deployment_mismatch", "Deployment ID mismatch");
            return;
        }

        if (onConfig) {
            ConfigUpdatePatch patch;
            snprintf(patch.request_id, sizeof(patch.request_id), "%s", requestId.c_str());
            String expiresAt = doc["expires_at"] | "";
            snprintf(patch.expires_at, sizeof(patch.expires_at), "%s", expiresAt.c_str());
            if (doc["version"].is<uint32_t>()) {
                patch.has_version = true;
                patch.version = doc["version"].as<uint32_t>();
            }
            if (doc["temp_max"].is<float>()) {
                float v = doc["temp_max"].as<float>();
                if (isfinite(v)) { patch.has_temp_max = true; patch.temp_max = v; }
            }
            if (doc["temp_min"].is<float>()) {
                float v = doc["temp_min"].as<float>();
                if (isfinite(v)) { patch.has_temp_min = true; patch.temp_min = v; }
            }
            if (doc["humi_max"].is<float>()) {
                float v = doc["humi_max"].as<float>();
                if (isfinite(v)) { patch.has_humi_max = true; patch.humi_max = v; }
            }
            if (doc["wind_max"].is<float>()) {
                float v = doc["wind_max"].as<float>();
                if (isfinite(v)) { patch.has_wind_max = true; patch.wind_max = v; }
            }
            if (doc["rain_max"].is<float>()) {
                float v = doc["rain_max"].as<float>();
                if (isfinite(v)) { patch.has_rain_max = true; patch.rain_max = v; }
            }
            if (doc["auto_warning"].is<bool>()) {
                patch.has_auto_warning = true;
                patch.auto_warning = doc["auto_warning"].as<bool>();
            }
            if (doc["buzzer"].is<bool>()) {
                patch.has_buzzer = true;
                patch.buzzer = doc["buzzer"].as<bool>();
            }
            onConfig(patch);
        }
    }
}

