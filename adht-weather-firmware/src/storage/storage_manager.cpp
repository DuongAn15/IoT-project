#include "storage_manager.h"
#include <string.h>

StorageManager storageMgr;

StorageManager::StorageManager() {}

void StorageManager::begin() {
    prefs.begin("adht_cfg", false);
    wifiPrefs.begin("adht_wifi", false);
}

void StorageManager::loadConfig(SystemConfig &cfg) {
    cfg.temp_max_alert = prefs.getFloat("t_max", 38.0f);
    cfg.temp_min_alert = prefs.getFloat("t_min", 10.0f);
    cfg.humi_max_alert = prefs.getFloat("h_max", 90.0f);
    cfg.wind_max_alert = prefs.getFloat("w_max", 15.0f);
    cfg.rain_max_alert = prefs.getFloat("r_max", 30.0f);
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

uint32_t StorageManager::computeWifiCrc(const WifiCredentialsRecord &rec) {
    // Standard CRC-32 (IEEE 802.3) over version, ssid, and password
    uint32_t crc = 0xFFFFFFFFu;
    auto updateBytes = [&crc](const uint8_t *data, size_t len) {
        for (size_t i = 0; i < len; ++i) {
            crc ^= data[i];
            for (int b = 0; b < 8; ++b) {
                crc = (crc >> 1) ^ (0xEDB88320u & (-(crc & 1u)));
            }
        }
    };
    updateBytes(reinterpret_cast<const uint8_t *>(&rec.version), sizeof(rec.version));
    updateBytes(reinterpret_cast<const uint8_t *>(rec.ssid), sizeof(rec.ssid));
    updateBytes(reinterpret_cast<const uint8_t *>(rec.password), sizeof(rec.password));
    return ~crc;
}

bool StorageManager::loadWifiCredentials(String &ssid, String &password) {
    WifiCredentialsRecord rec;
    size_t readLen = wifiPrefs.getBytes("creds", &rec, sizeof(rec));
    if (readLen != sizeof(rec)) {
        return false;
    }
    if (rec.version != WifiCredentialsRecord::CURRENT_VERSION) {
        return false;
    }
    if (rec.crc32 != computeWifiCrc(rec)) {
        Serial.println("[STORAGE] Wi-Fi NVS record checksum mismatch!");
        return false;
    }
    rec.ssid[sizeof(rec.ssid) - 1] = '\0';
    rec.password[sizeof(rec.password) - 1] = '\0';
    if (rec.ssid[0] == '\0') {
        return false;
    }
    ssid = String(rec.ssid);
    password = String(rec.password);
    return true;
}

bool StorageManager::saveWifiCredentials(const String &ssid, const String &password) {
    if (ssid.length() == 0 || ssid.length() >= sizeof(WifiCredentialsRecord::ssid) ||
        password.length() >= sizeof(WifiCredentialsRecord::password)) {
        return false;
    }

    WifiCredentialsRecord rec;
    memset(&rec, 0, sizeof(rec));
    rec.version = WifiCredentialsRecord::CURRENT_VERSION;
    snprintf(rec.ssid, sizeof(rec.ssid), "%s", ssid.c_str());
    snprintf(rec.password, sizeof(rec.password), "%s", password.c_str());
    rec.crc32 = computeWifiCrc(rec);

    size_t written = wifiPrefs.putBytes("creds", &rec, sizeof(rec));
    if (written != sizeof(rec)) {
        return false;
    }

    // Read-back verification before declaring persistence successful
    String verifySsid;
    String verifyPass;
    if (!loadWifiCredentials(verifySsid, verifyPass)) {
        return false;
    }
    return verifySsid == ssid && verifyPass == password;
}

bool StorageManager::hasWifiCredentials() {
    String s, p;
    return loadWifiCredentials(s, p);
}
