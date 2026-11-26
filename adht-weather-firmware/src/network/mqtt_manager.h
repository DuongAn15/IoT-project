#ifndef MQTT_MANAGER_H
#define MQTT_MANAGER_H

#include "../config.h"
#include "../types.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>

typedef void (*CommandCallback)(const String &cmd, const String &payload);
typedef void (*ConfigUpdateCallback)(const ConfigUpdatePatch &patch);

class MqttManager {
public:
    MqttManager();
    void begin();
    void loop();
    bool isConnected();
    void publishTelemetry(const WeatherData &data, int rssi);
    void publishMinuteLog(const MinuteLogSample &sample);
    void setCommandCallback(CommandCallback cb);
    void setConfigCallback(ConfigUpdateCallback cb);

private:
    static constexpr size_t TELEMETRY_BACKLOG_CAPACITY = 12;
    static constexpr size_t TELEMETRY_PAYLOAD_MAX_BYTES = 896;

    struct BacklogEntry {
        char topic[72];
        char payload[TELEMETRY_PAYLOAD_MAX_BYTES];
    };

    WiFiClientSecure secureClient;
    PubSubClient mqttClient;
    uint32_t lastReconnectAttempt;
    CommandCallback onCommand;
    ConfigUpdateCallback onConfig;

    char bootId[17];
    uint32_t telemetrySequence;
    BacklogEntry backlog[TELEMETRY_BACKLOG_CAPACITY];
    size_t backlogHead;
    size_t backlogCount;

    void enqueueBacklog(const char *topic, const char *payload);
    void flushBacklog();
    bool reconnect();
    void onMessageReceived(char *topic, byte *payload, unsigned int length);
    static void staticCallback(char *topic, byte *payload, unsigned int length);
};

extern MqttManager mqttMgr;

#endif // MQTT_MANAGER_H
