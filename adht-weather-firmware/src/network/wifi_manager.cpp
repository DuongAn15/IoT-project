#include "wifi_manager.h"

WifiManager wifiMgr;

WifiManager::WifiManager()
    : lastCheckTime(0),
      disconnectedSinceMs(0),
      wasDisconnected(false)
{
    statusMux = portMUX_INITIALIZER_UNLOCKED;
}

void WifiManager::begin() {
    Serial.println("[WiFi] Connecting to: " DEFAULT_WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(DEFAULT_WIFI_SSID, DEFAULT_WIFI_PASS);
}

void WifiManager::loop() {
    uint32_t now = millis();
    if (static_cast<uint32_t>(now - lastCheckTime) > 5000) {
        lastCheckTime = now;
        wl_status_t currentStatus = WiFi.status();

        if (currentStatus == WL_CONNECTED) {
            bool justConnected = false;
            int rssi = WiFi.RSSI();
            String ipStr = WiFi.localIP().toString();

            portENTER_CRITICAL(&statusMux);
            justConnected = !status.wifi_connected;
            status.wifi_connected = true;
            status.wifi_rssi = rssi;
            snprintf(status.ip_address, sizeof(status.ip_address), "%s", ipStr.c_str());
            portEXIT_CRITICAL(&statusMux);

            wasDisconnected = false;
            disconnectedSinceMs = 0;

            if (justConnected) {
                Serial.println("[WiFi] Connected successfully!");
                Serial.printf("[WiFi] IP Address: %s (RSSI: %d dBm)\n", ipStr.c_str(), rssi);
            }
        } else {
            portENTER_CRITICAL(&statusMux);
            status.wifi_connected = false;
            status.wifi_rssi = 0;
            snprintf(status.ip_address, sizeof(status.ip_address), "Disconnected");
            portEXIT_CRITICAL(&statusMux);

            if (!wasDisconnected) {
                wasDisconnected = true;
                disconnectedSinceMs = now;
            }

            bool stuckDisconnected = static_cast<uint32_t>(now - disconnectedSinceMs) >= WIFI_FORCE_RECONNECT_MS;
            if ((currentStatus != WL_IDLE_STATUS && currentStatus != WL_DISCONNECTED) || stuckDisconnected) {
                Serial.printf("[WiFi] Status code: %d (%s). Re-attempting connection...\n",
                              currentStatus, stuckDisconnected ? "timeout fallback" : "state error");
                disconnectedSinceMs = now;
                WiFi.disconnect(false);
                WiFi.begin(DEFAULT_WIFI_SSID, DEFAULT_WIFI_PASS);
            } else {
                Serial.println("[WiFi] Still connecting...");
            }
        }
    }
}

bool WifiManager::isConnected() {
    return WiFi.status() == WL_CONNECTED;
}

NetworkStatus WifiManager::getStatus() {
    NetworkStatus copy;
    portENTER_CRITICAL(&statusMux);
    copy = status;
    portEXIT_CRITICAL(&statusMux);
    return copy;
}
