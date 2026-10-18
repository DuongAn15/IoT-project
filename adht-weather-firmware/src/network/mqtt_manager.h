#ifndef MQTT_MANAGER_H
#define MQTT_MANAGER_H

#include "../config.h"
#include "../types.h"
#include <WiFiClientSecure.h>
#include <PubSubClient.h>

typedef void (*CommandCallback)(const String &cmd, const String &payload);
typedef void (*ConfigUpdateCallback)(const SystemConfig &newCfg);

class MqttManager {
public:
    MqttManager();
    void begin();
    void loop();
    bool isConnected();
    void publishTelemetry(const WeatherData &data, int rssi);
    void setCommandCallback(CommandCallback cb);
    void setConfigCallback(ConfigUpdateCallback cb);

private:
    WiFiClientSecure secureClient;
    PubSubClient mqttClient;
    uint32_t lastReconnectAttempt;
    CommandCallback onCommand;
    ConfigUpdateCallback onConfig;

    bool reconnect();
    void onMessageReceived(char *topic, byte *payload, unsigned int length);
    static void staticCallback(char *topic, byte *payload, unsigned int length);
};

extern MqttManager mqttMgr;

#endif // MQTT_MANAGER_H

