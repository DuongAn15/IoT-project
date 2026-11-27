#ifndef STORAGE_MANAGER_H
#define STORAGE_MANAGER_H

#include "../types.h"
#include <Preferences.h>

class StorageManager {
public:
    StorageManager();
    void begin();
    void loadConfig(SystemConfig &cfg);
    bool saveConfig(const SystemConfig &cfg);
    int commandRequestState(const String &requestId); // 0 absent, 1 pending, 2 applied
    bool rememberCommandRequest(const String &requestId);
    bool markCommandApplied(const String &requestId);
    bool savePendingAck(const String &payload);
    String pendingAck(size_t index);
    void clearPendingAck(size_t index);
    static constexpr size_t ACK_SLOTS = 8;

    bool loadWifiCredentials(String &ssid, String &password);
    bool saveWifiCredentials(const String &ssid, const String &password);
    bool hasWifiCredentials();

private:
    Preferences prefs;
    Preferences wifiPrefs;
    Preferences operationPrefs;
    static constexpr size_t COMMAND_SLOTS = 64;
    static uint32_t computeConfigCrc(const SystemConfigNvsRecord &rec);
    static uint32_t computeWifiCrc(const WifiCredentialsRecord &rec);
};

extern StorageManager storageMgr;

#endif // STORAGE_MANAGER_H
