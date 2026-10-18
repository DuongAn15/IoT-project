#include "wifi_manager.h"

WifiManager wifiMgr;

WifiManager::WifiManager() : lastCheckTime(0) {}

void WifiManager::begin() {
    Serial.println("[WiFi] Connecting to: " DEFAULT_WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(DEFAULT_WIFI_SSID, DEFAULT_WIFI_PASS);
}

void WifiManager::loop() {
    uint32_t now = millis();
    if (now - lastCheckTime > 5000) {
        lastCheckTime = now;
        if (WiFi.status() == WL_CONNECTED) {
            status.wifi_connected = true;
            status.wifi_rssi = WiFi.RSSI();
            status.ip_address = WiFi.localIP().toString();
        } else {
            status.wifi_connected = false;
            status.ip_address = "Disconnected";
            Serial.println("[WiFi] Disconnected. Reconnecting...");
            WiFi.reconnect();
        }
    }
}

bool WifiManager::isConnected() {
    return WiFi.status() == WL_CONNECTED;
}

NetworkStatus WifiManager::getStatus() {
    return status;
}

