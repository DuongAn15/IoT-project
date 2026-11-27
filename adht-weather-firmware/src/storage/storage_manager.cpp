#include "storage_manager.h"
#include <string.h>
#include <time.h>
#include <stdlib.h>

StorageManager storageMgr;

StorageManager::StorageManager() {}

void StorageManager::begin() {
    prefs.begin("adht_cfg", false);
    wifiPrefs.begin("adht_wifi", false);
    operationPrefs.begin("adht_ops", false);
}

// Keep command IDs longer than the maximum backend TTL (3600 seconds).
static constexpr time_t COMMAND_ID_RETENTION_SEC = 3900;

static String commandIdFromRecord(const String &value) {
    int separator = value.indexOf(':', 2);
    return separator < 0 ? "" : value.substring(separator + 1);
}

int StorageManager::commandRequestState(const String &requestId) {
    if (requestId.isEmpty()) return 0;
    for (size_t i = 0; i < COMMAND_SLOTS; ++i) {
        char key[12];
        snprintf(key, sizeof(key), "cmd_%u", static_cast<unsigned>(i));
        String value = operationPrefs.getString(key, "");
        if (commandIdFromRecord(value) != requestId) continue;
        if (value.startsWith("A:")) return 2;
        if (value.startsWith("P:")) return 1;
    }
    return 0;
}

bool StorageManager::rememberCommandRequest(const String &requestId) {
    if (requestId.isEmpty()) return true; // Legacy command without P06 ID.
    if (commandRequestState(requestId) != 0) return true;
    const uint32_t head = operationPrefs.getUInt("cmd_head", 0) % COMMAND_SLOTS;
    const time_t now = time(nullptr);
    for (size_t offset = 0; offset < COMMAND_SLOTS; ++offset) {
        size_t slot = (head + offset) % COMMAND_SLOTS;
        char key[12];
        snprintf(key, sizeof(key), "cmd_%u", static_cast<unsigned>(slot));
        String old = operationPrefs.getString(key, "");
        time_t writtenAt = old.length() > 2
            ? static_cast<time_t>(strtoll(old.c_str() + 2, nullptr, 10)) : 0;
        if (!old.isEmpty() && (writtenAt <= 0 || now < writtenAt ||
            now - writtenAt <= COMMAND_ID_RETENTION_SEC)) continue;
        String value = "P:" + String(static_cast<long long>(now)) + ":" + requestId;
        if (operationPrefs.putString(key, value) != value.length() ||
            operationPrefs.getString(key, "") != value) return false;
        operationPrefs.putUInt("cmd_head", (slot + 1) % COMMAND_SLOTS);
        return true; // Marker is durable even if the head write fails.
    }
    return false; // Never evict an unexpired ID and risk running a duplicate.
}

bool StorageManager::markCommandApplied(const String &requestId) {
    if (requestId.isEmpty()) return true;
    for (size_t i = 0; i < COMMAND_SLOTS; ++i) {
        char key[12];
        snprintf(key, sizeof(key), "cmd_%u", static_cast<unsigned>(i));
        String old = operationPrefs.getString(key, "");
        if (!old.startsWith("P:") || commandIdFromRecord(old) != requestId) continue;
        String value = "A" + old.substring(1);
        return operationPrefs.putString(key, value) == value.length() &&
            operationPrefs.getString(key, "") == value;
    }
    return false;
}

bool StorageManager::savePendingAck(const String &payload) {
    if (payload.isEmpty() || payload.length() > 383) return false;
    for (size_t i = 0; i < ACK_SLOTS; ++i) {
        char key[12];
        snprintf(key, sizeof(key), "ack_%u", static_cast<unsigned>(i));
        if (operationPrefs.getString(key, "").isEmpty()) {
            return operationPrefs.putString(key, payload) == payload.length() &&
                operationPrefs.getString(key, "") == payload;
        }
    }
    return false;
}

String StorageManager::pendingAck(size_t index) {
    if (index >= ACK_SLOTS) return "";
    char key[12];
    snprintf(key, sizeof(key), "ack_%u", static_cast<unsigned>(index));
    return operationPrefs.getString(key, "");
}

void StorageManager::clearPendingAck(size_t index) {
    if (index >= ACK_SLOTS) return;
    char key[12];
    snprintf(key, sizeof(key), "ack_%u", static_cast<unsigned>(index));
    operationPrefs.remove(key);
}

uint32_t StorageManager::computeConfigCrc(const SystemConfigNvsRecord &rec) {
    uint32_t crc = 0xFFFFFFFFu;
    auto updateBytes = [&crc](const uint8_t *data, size_t len) {
        for (size_t i = 0; i < len; ++i) {
            crc ^= data[i];
            for (int b = 0; b < 8; ++b) {
                crc = (crc >> 1) ^ (0xEDB88320u & (-(crc & 1u)));
            }
        }
    };
    updateBytes(reinterpret_cast<const uint8_t *>(&rec.magic), sizeof(rec.magic));
    updateBytes(reinterpret_cast<const uint8_t *>(&rec.config), sizeof(rec.config));
    return ~crc;
}

void StorageManager::loadConfig(SystemConfig &cfg) {
    SystemConfigNvsRecord rec;
    size_t readLen = prefs.getBytes("cfg_rec", &rec, sizeof(rec));
    if (readLen == sizeof(rec) &&
        rec.magic == SystemConfigNvsRecord::MAGIC_VERSION &&
        rec.crc32 == computeConfigCrc(rec)) {
        cfg = rec.config;
        return;
    }

    // Fallback for legacy unversioned NVS keys
    cfg.version = 0;
    cfg.temp_max_alert = prefs.getFloat("t_max", 38.0f);
    cfg.temp_min_alert = prefs.getFloat("t_min", 10.0f);
    cfg.humi_max_alert = prefs.getFloat("h_max", 90.0f);
    cfg.wind_max_alert = prefs.getFloat("w_max", 15.0f);
    cfg.rain_max_alert = prefs.getFloat("r_max", 30.0f);
    cfg.buzzer_enabled = prefs.getBool("bz_en", true);
    cfg.auto_warning_enabled = prefs.getBool("w_en", true);
}

bool StorageManager::saveConfig(const SystemConfig &cfg) {
    SystemConfigNvsRecord rec;
    memset(&rec, 0, sizeof(rec));
    rec.magic = SystemConfigNvsRecord::MAGIC_VERSION;
    rec.config = cfg;
    rec.crc32 = computeConfigCrc(rec);

    size_t written = prefs.putBytes("cfg_rec", &rec, sizeof(rec));
    if (written != sizeof(rec)) {
        return false;
    }

    // Read-back verification before declaring NVS persistence successful
    SystemConfigNvsRecord verifyRec;
    size_t verifyLen = prefs.getBytes("cfg_rec", &verifyRec, sizeof(verifyRec));
    if (verifyLen != sizeof(verifyRec) ||
        verifyRec.magic != SystemConfigNvsRecord::MAGIC_VERSION ||
        verifyRec.crc32 != computeConfigCrc(verifyRec) ||
        verifyRec.config.version != cfg.version) {
        return false;
    }

    prefs.putFloat("t_max", cfg.temp_max_alert);
    prefs.putFloat("t_min", cfg.temp_min_alert);
    prefs.putFloat("h_max", cfg.humi_max_alert);
    prefs.putFloat("w_max", cfg.wind_max_alert);
    prefs.putFloat("r_max", cfg.rain_max_alert);
    prefs.putBool("bz_en", cfg.buzzer_enabled);
    prefs.putBool("w_en", cfg.auto_warning_enabled);
    return true;
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
