#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include "../config.h"
#include "../types.h"
#include <WiFi.h>

class WifiManager {
public:
    WifiManager();
    void begin();
    void loop();
    bool isConnected();
    NetworkStatus getStatus();

private:
    uint32_t lastCheckTime;
    uint32_t disconnectedSinceMs;
    bool wasDisconnected;
    portMUX_TYPE statusMux;
    NetworkStatus status;
};

extern WifiManager wifiMgr;

#endif // WIFI_MANAGER_H

