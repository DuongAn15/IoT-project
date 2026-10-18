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
    NetworkStatus status;
};

extern WifiManager wifiMgr;

#endif // WIFI_MANAGER_H

