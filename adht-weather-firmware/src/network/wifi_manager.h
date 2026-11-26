#ifndef WIFI_MANAGER_H
#define WIFI_MANAGER_H

#include "../config.h"
#include "../types.h"
#include <WiFi.h>
#include <WebServer.h>
#include <DNSServer.h>

class WifiManager {
public:
    WifiManager();
    void begin();
    void loop();
    bool isConnected();
    bool isProvisioning();
    void requestProvisioningPortal();
    NetworkStatus getStatus();

private:
    enum class Mode {
        STA,
        PROVISIONING
    };

    Mode mode;
    uint32_t lastCheckTime;
    uint32_t lastReconnectAttemptMs;
    uint32_t backoffMs;
    uint32_t portalStartedMs;
    bool provisioningRequested;
    bool pendingRebootAfterSave;
    uint32_t pendingRebootMs;

    String activeSsid;
    String activePassword;
    String apSsid;
    String apPassword;

    WebServer webServer;
    DNSServer dnsServer;
    bool portalRunning;

    portMUX_TYPE statusMux;
    NetworkStatus status;

    void startSta();
    void startProvisioningPortal();
    void stopProvisioningPortal();
    void handleStaLoop(uint32_t now);
    void handlePortalLoop(uint32_t now);
    void generateApCredentials();
    void setupWebRoutes();
    void handlePortalRoot();
    void handlePortalSave();
    void handlePortalCancel();
    bool testCandidateCredentials(const String &ssid, const String &pass);
};

extern WifiManager wifiMgr;

#endif // WIFI_MANAGER_H
