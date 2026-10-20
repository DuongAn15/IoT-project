#include "wifi_manager.h"

WifiManager wifiMgr;

WifiManager::WifiManager() : lastCheckTime(0) {}

void WifiManager::begin() {
    Serial.println("[WiFi] Connecting to: " DEFAULT_WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(true);
    WiFi.begin(DEFAULT_WIFI_SSID, DEFAULT_WIFI_PASS);
}

void WifiManager::loop() {
    uint32_t now = millis();
    if (now - lastCheckTime > 5000) {
        lastCheckTime = now;
        wl_status_t currentStatus = WiFi.status();

        if (currentStatus == WL_CONNECTED) {
            if (!status.wifi_connected) {
                Serial.println("[WiFi] Connected successfully!");
                Serial.printf("[WiFi] IP Address: %s (RSSI: %d dBm)\n", 
                              WiFi.localIP().toString().c_str(), WiFi.RSSI());
            }
            status.wifi_connected = true;
            status.wifi_rssi = WiFi.RSSI();
            status.ip_address = WiFi.localIP().toString();
        } else {
            status.wifi_connected = false;
            status.ip_address = "Disconnected";
            
            // Only force re-connect if not actively in connecting phase
            if (currentStatus != WL_IDLE_STATUS && currentStatus != WL_DISCONNECTED) {
                Serial.printf("[WiFi] Status code: %d. Re-attempting connection...\n", currentStatus);
                WiFi.disconnect();
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
    return status;
}
