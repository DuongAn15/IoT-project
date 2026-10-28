#include "mqtt_manager.h"
#include <ArduinoJson.h>

MqttManager mqttMgr;

void MqttManager::staticCallback(char *topic, byte *payload, unsigned int length) {
    mqttMgr.onMessageReceived(topic, payload, length);
}

MqttManager::MqttManager() 
    : mqttClient(secureClient),
      lastReconnectAttempt(0),
      onCommand(nullptr),
      onConfig(nullptr)
{}

void MqttManager::begin() {
    // Enable insecure TLS so we do not have to hardcode changing root CA certificates
    secureClient.setInsecure();
    
    mqttClient.setServer(MQTT_BROKER_HOST, MQTT_BROKER_PORT);
    mqttClient.setCallback(staticCallback);
    mqttClient.setBufferSize(512);
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

    Serial.printf("[MQTT] Connecting to %s:%d...\n", MQTT_BROKER_HOST, MQTT_BROKER_PORT);

    // Last Will and Testament (LWT)
    const char *willTopic = TOPIC_STATUS;
    const char *willMessage = "{\"status\":\"offline\"}";
    int willQos = 1;
    bool willRetain = true;

    if (mqttClient.connect(DEVICE_ID, MQTT_USERNAME, MQTT_PASSWORD, 
                           willTopic, willQos, willRetain, willMessage)) {
        Serial.println("[MQTT] Connected successfully!");

        // Publish Online Status (Retained)
        char onlinePayload[128];
        snprintf(onlinePayload, sizeof(onlinePayload), 
                 "{\"status\":\"online\",\"device\":\"%s\",\"ip\":\"%s\"}",
                 DEVICE_ID, WiFi.localIP().toString().c_str());
        mqttClient.publish(TOPIC_STATUS, onlinePayload, true);

        // Subscribe to Command & Config topics
        mqttClient.subscribe(TOPIC_COMMAND, 1);
        mqttClient.subscribe(TOPIC_CONFIG, 1);
        Serial.printf("[MQTT] Subscribed to %s and %s\n", TOPIC_COMMAND, TOPIC_CONFIG);
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
            reconnect();
        }
    } else {
        mqttClient.loop();
    }
}

bool MqttManager::isConnected() {
    return mqttClient.connected();
}

void MqttManager::publishTelemetry(const WeatherData &data, int rssi) {
    if (!mqttClient.connected()) return;

    JsonDocument doc;
    doc["device_id"] = DEVICE_ID;
    doc["temp"] = round(data.temperature * 10.0f) / 10.0f;
    doc["humi"] = round(data.humidity * 10.0f) / 10.0f;
    doc["rain_rate"] = round(data.rain_rate * 100.0f) / 100.0f;
    doc["rain_total"] = round(data.rain_total * 100.0f) / 100.0f;
    doc["wind_speed"] = round(data.wind_speed * 10.0f) / 10.0f;
    doc["wind_max"] = round(data.wind_max * 10.0f) / 10.0f;
    doc["rssi"] = rssi;
    doc["uptime"] = millis() / 1000;

    char buffer[384];
    serializeJson(doc, buffer, sizeof(buffer));

    bool ok = mqttClient.publish(TOPIC_TELEMETRY, buffer);
    if (ok) {
        Serial.printf("[MQTT] Published telemetry: %s\n", buffer);
    } else {
        Serial.println("[MQTT] Publish telemetry failed!");
    }
}

void MqttManager::onMessageReceived(char *topic, byte *payload, unsigned int length) {
    String msg;
    for (unsigned int i = 0; i < length; i++) {
        msg += (char)payload[i];
    }
    Serial.printf("[MQTT] Received on %s: %s\n", topic, msg.c_str());

    // 1. Command handling
    if (String(topic) == TOPIC_COMMAND) {
        JsonDocument doc;
        DeserializationError err = deserializeJson(doc, msg);
        if (!err) {
            String cmd = doc["cmd"] | "";
            String arg = doc["arg"] | "";
            if (onCommand) onCommand(cmd, arg);
        }
    }
    // 2. Config update handling
    else if (String(topic) == TOPIC_CONFIG) {
        JsonDocument doc;
        DeserializationError err = deserializeJson(doc, msg);
        if (!err && onConfig) {
            SystemConfig cfg;
            cfg.temp_max_alert = doc["temp_max"] | 38.0f;
            cfg.temp_min_alert = doc["temp_min"] | 10.0f;
            cfg.humi_max_alert = doc["humi_max"] | 90.0f;
            cfg.wind_max_alert = doc["wind_max"] | 15.0f;
            cfg.rain_max_alert = doc["rain_max"] | 50.0f;
            cfg.auto_warning_enabled = doc["auto_warning"] | true;
            cfg.buzzer_enabled = doc["buzzer"] | true;
            onConfig(cfg);
        }
    }
}

