#ifndef STORAGE_MANAGER_H
#define STORAGE_MANAGER_H

#include "../types.h"
#include <Preferences.h>

class StorageManager {
public:
    StorageManager();
    void begin();
    void loadConfig(SystemConfig &cfg);
    void saveConfig(const SystemConfig &cfg);

    bool loadWifiCredentials(String &ssid, String &password);
    bool saveWifiCredentials(const String &ssid, const String &password);
    bool hasWifiCredentials();

private:
    Preferences prefs;
    Preferences wifiPrefs;
    static uint32_t computeWifiCrc(const WifiCredentialsRecord &rec);
};

extern StorageManager storageMgr;

#endif // STORAGE_MANAGER_H
