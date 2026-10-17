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

private:
    Preferences prefs;
};

extern StorageManager storageMgr;

#endif // STORAGE_MANAGER_H

