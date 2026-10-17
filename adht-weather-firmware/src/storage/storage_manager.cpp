#include "storage_manager.h"

StorageManager storageMgr;

StorageManager::StorageManager() {}

void StorageManager::begin() {
    prefs.begin("adht_cfg", false);
}

void StorageManager::loadConfig(SystemConfig &cfg) {
    cfg.temp_max_alert = prefs.getFloat("t_max", 38.0f);
    cfg.temp_min_alert = prefs.getFloat("t_min", 10.0f);
    cfg.humi_max_alert = prefs.getFloat("h_max", 90.0f);
    cfg.wind_max_alert = prefs.getFloat("w_max", 15.0f);
    cfg.rain_max_alert = prefs.getFloat("r_max", 50.0f);
    cfg.buzzer_enabled = prefs.getBool("bz_en", true);
    cfg.auto_warning_enabled = prefs.getBool("w_en", true);
}

void StorageManager::saveConfig(const SystemConfig &cfg) {
    prefs.putFloat("t_max", cfg.temp_max_alert);
    prefs.putFloat("t_min", cfg.temp_min_alert);
    prefs.putFloat("h_max", cfg.humi_max_alert);
    prefs.putFloat("w_max", cfg.wind_max_alert);
    prefs.putFloat("r_max", cfg.rain_max_alert);
    prefs.putBool("bz_en", cfg.buzzer_enabled);
    prefs.putBool("w_en", cfg.auto_warning_enabled);
}

