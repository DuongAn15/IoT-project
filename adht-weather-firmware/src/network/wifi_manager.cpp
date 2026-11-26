#include "wifi_manager.h"
#include "../storage/storage_manager.h"
#include <esp_system.h>
#include <esp_task_wdt.h>

WifiManager wifiMgr;

namespace {
const IPAddress AP_IP(192, 168, 4, 1);
const IPAddress AP_NETMASK(255, 255, 255, 0);

String htmlEscape(const String &in) {
    String out;
    out.reserve(in.length());
    for (size_t i = 0; i < in.length(); ++i) {
        char c = in[i];
        if (c == '&') out += "&amp;";
        else if (c == '<') out += "&lt;";
        else if (c == '>') out += "&gt;";
        else if (c == '"') out += "&quot;";
        else out += c;
    }
    return out;
}
} // namespace

WifiManager::WifiManager()
    : mode(Mode::STA),
      lastCheckTime(0),
      lastReconnectAttemptMs(0),
      backoffMs(WIFI_BACKOFF_MIN_MS),
      portalStartedMs(0),
      provisioningRequested(false),
      pendingRebootAfterSave(false),
      pendingRebootMs(0),
      webServer(80),
      portalRunning(false)
{
    statusMux = portMUX_INITIALIZER_UNLOCKED;
}

void WifiManager::begin() {
    if (storageMgr.loadWifiCredentials(activeSsid, activePassword)) {
        Serial.println("[WiFi] Loaded credentials from NVS; starting STA mode.");
        startSta();
    } else {
        Serial.println("[WiFi] No valid Wi-Fi credentials in NVS; starting provisioning portal.");
        startProvisioningPortal();
    }
}

void WifiManager::requestProvisioningPortal() {
    portENTER_CRITICAL(&statusMux);
    provisioningRequested = true;
    portEXIT_CRITICAL(&statusMux);
}

bool WifiManager::isProvisioning() {
    portENTER_CRITICAL(&statusMux);
    bool active = status.provisioning_active;
    portEXIT_CRITICAL(&statusMux);
    return active;
}

void WifiManager::generateApCredentials() {
    uint64_t mac = ESP.getEfuseMac();
    uint16_t suffix = static_cast<uint16_t>((mac >> 32) ^ (mac & 0xFFFFu));
    char ssidBuf[24];
    snprintf(ssidBuf, sizeof(ssidBuf), "ADHT-Setup-%04X", suffix);
    apSsid = String(ssidBuf);

    // 10-character unambiguous alphanumeric WPA2 password via hardware RNG
    static const char charset[] = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789abcdefghjkmnpqrstuvwxyz";
    char passBuf[11];
    for (int i = 0; i < 10; ++i) {
        passBuf[i] = charset[esp_random() % (sizeof(charset) - 1)];
    }
    passBuf[10] = '\0';
    apPassword = String(passBuf);
}

void WifiManager::startSta() {
    stopProvisioningPortal();
    mode = Mode::STA;
    backoffMs = WIFI_BACKOFF_MIN_MS;
    lastReconnectAttemptMs = millis();

    WiFi.mode(WIFI_STA);
    WiFi.setAutoReconnect(false);
    WiFi.begin(activeSsid.c_str(), activePassword.c_str());

    portENTER_CRITICAL(&statusMux);
    status.provisioning_active = false;
    status.wifi_connected = false;
    status.wifi_rssi = 0;
    snprintf(status.ip_address, sizeof(status.ip_address), "Connecting");
    status.ap_ssid[0] = '\0';
    status.ap_pass[0] = '\0';
    portEXIT_CRITICAL(&statusMux);
}

void WifiManager::startProvisioningPortal() {
    generateApCredentials();
    mode = Mode::PROVISIONING;
    portalStartedMs = millis();

    WiFi.disconnect(false);
    WiFi.mode(WIFI_AP);
    WiFi.softAPConfig(AP_IP, AP_IP, AP_NETMASK);
    WiFi.softAP(apSsid.c_str(), apPassword.c_str());

    dnsServer.start(53, "*", AP_IP);
    setupWebRoutes();
    webServer.begin();
    portalRunning = true;

    portENTER_CRITICAL(&statusMux);
    status.provisioning_active = true;
    status.wifi_connected = false;
    status.wifi_rssi = 0;
    snprintf(status.ip_address, sizeof(status.ip_address), "192.168.4.1");
    snprintf(status.ap_ssid, sizeof(status.ap_ssid), "%s", apSsid.c_str());
    snprintf(status.ap_pass, sizeof(status.ap_pass), "%s", apPassword.c_str());
    snprintf(status.ap_url, sizeof(status.ap_url), "http://192.168.4.1");
    portEXIT_CRITICAL(&statusMux);

    // Do not log AP password to Serial; user reads it from OLED screen.
    Serial.printf("[WiFi] Provisioning AP started: %s (http://192.168.4.1)\n", apSsid.c_str());
}

void WifiManager::stopProvisioningPortal() {
    if (portalRunning) {
        webServer.stop();
        dnsServer.stop();
        WiFi.softAPdisconnect(true);
        portalRunning = false;
    }
}

void WifiManager::setupWebRoutes() {
    webServer.on("/", HTTP_GET, [this]() { handlePortalRoot(); });
    webServer.on("/save", HTTP_POST, [this]() { handlePortalSave(); });
    webServer.on("/cancel", HTTP_POST, [this]() { handlePortalCancel(); });
    webServer.onNotFound([this]() { handlePortalRoot(); });
}

void WifiManager::handlePortalRoot() {
    String cancelBtn = "";
    if (storageMgr.hasWifiCredentials()) {
        cancelBtn =
            "<form method='POST' action='/cancel' style='margin-top:12px'>"
            "<button type='submit' style='background:#5f6368'>Hủy &amp; Kết nối lại Wi-Fi cũ</button>"
            "</form>";
    }
    String html =
        "<!DOCTYPE html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>Config Wi-Fi cho</title>"
        "<style>body{font-family:sans-serif;max-width:420px;margin:24px auto;padding:0 16px}"
        "p{color:#444;font-size:14px}input{width:100%;padding:10px;margin:8px 0 16px;box-sizing:border-box}"
        "button{width:100%;padding:12px;background:#0b57d0;color:#fff;border:0;border-radius:6px;font-size:16px}</style>"
        "</head><body><h2>Config Wi-Fi cho Trạm Thời Tiết ADHT</h2>"
        "<p>Nhập tên mạng và mật khẩu Wi-Fi mới cho thiết bị (không phải đăng nhập tài khoản).</p>"
        "<form method='POST' action='/save'>"
        "<label>Tên Wi-Fi (SSID)</label><input name='ssid' maxlength='32' required value='" + htmlEscape(activeSsid) + "'>"
        "<label>Mật khẩu Wi-Fi</label><input name='password' type='password' maxlength='64'>"
        "<button type='submit'>Kiểm tra &amp; Lưu Wi-Fi</button></form>" + cancelBtn + "</body></html>";
    webServer.send(200, "text/html", html);
}

void WifiManager::handlePortalCancel() {
    if (!storageMgr.hasWifiCredentials()) {
        webServer.send(400, "text/html", "<h3>Chưa có thông tin Wi-Fi cũ trong bộ nhớ.</h3><a href='/'>Quay lại</a>");
        return;
    }
    webServer.send(200, "text/html", "<h3>Đã hủy. Thiết bị đang kết nối lại Wi-Fi cũ...</h3>");
    delay(300);
    Serial.println("[WiFi] Provisioning cancelled by user; resuming STA with previous credentials.");
    startSta();
}

bool WifiManager::testCandidateCredentials(const String &ssid, const String &pass) {
    WiFi.mode(WIFI_AP_STA);
    WiFi.begin(ssid.c_str(), pass.c_str());

    uint32_t start = millis();
    while (static_cast<uint32_t>(millis() - start) < 15000) {
        esp_task_wdt_reset();
        dnsServer.processNextRequest();
        if (WiFi.status() == WL_CONNECTED) {
            return true;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }
    WiFi.disconnect(false);
    WiFi.mode(WIFI_AP);
    return false;
}

void WifiManager::handlePortalSave() {
    String newSsid = webServer.arg("ssid");
    String newPass = webServer.arg("password");
    newSsid.trim();

    if (newSsid.length() == 0 || newSsid.length() >= sizeof(WifiCredentialsRecord::ssid) ||
        newPass.length() >= sizeof(WifiCredentialsRecord::password)) {
        webServer.send(400, "text/html",
                       "<h3>Tên Wi-Fi hoặc mật khẩu không hợp lệ.</h3><a href='/'>Quay lại</a>");
        return;
    }

    Serial.println("[WiFi] Testing candidate Wi-Fi credentials from portal...");
    if (!testCandidateCredentials(newSsid, newPass)) {
        Serial.println("[WiFi] Candidate Wi-Fi failed; keeping previous NVS credentials.");
        String cancelForm = storageMgr.hasWifiCredentials()
            ? "<form method='POST' action='/cancel' style='margin-top:12px'><button type='submit'>Hủy &amp; Kết nối lại Wi-Fi cũ</button></form>"
            : "";
        webServer.send(400, "text/html",
                       "<h3>Không kết nối được Wi-Fi mới. Đã giữ nguyên Wi-Fi cũ.</h3>"
                       "<a href='/'>Thử lại</a>" + cancelForm);
        return;
    }

    if (!storageMgr.saveWifiCredentials(newSsid, newPass)) {
        webServer.send(500, "text/html",
                       "<h3>Lỗi lưu NVS. Đã giữ nguyên Wi-Fi cũ.</h3><a href='/'>Thử lại</a>");
        return;
    }

    activeSsid = newSsid;
    activePassword = newPass;
    pendingRebootAfterSave = true;
    pendingRebootMs = millis();

    webServer.send(200, "text/html",
                   "<h3>Đã xác minh &amp; lưu Wi-Fi thành công! Trạm đang khởi động lại...</h3>");
    Serial.println("[WiFi] New credentials verified and saved to NVS; reboot scheduled.");
}

void WifiManager::handleStaLoop(uint32_t now) {
    if (static_cast<uint32_t>(now - lastCheckTime) <= 1000) {
        return;
    }
    lastCheckTime = now;

    wl_status_t currentStatus = WiFi.status();
    if (currentStatus == WL_CONNECTED) {
        bool justConnected = false;
        int rssi = WiFi.RSSI();
        String ipStr = WiFi.localIP().toString();

        portENTER_CRITICAL(&statusMux);
        justConnected = !status.wifi_connected;
        status.wifi_connected = true;
        status.wifi_rssi = rssi;
        snprintf(status.ip_address, sizeof(status.ip_address), "%s", ipStr.c_str());
        portEXIT_CRITICAL(&statusMux);

        backoffMs = WIFI_BACKOFF_MIN_MS;
        lastReconnectAttemptMs = now;

        if (justConnected) {
            Serial.println("[WiFi] Connected successfully!");
            Serial.printf("[WiFi] IP Address: %s (RSSI: %d dBm)\n", ipStr.c_str(), rssi);
            configTime(0, 0, "pool.ntp.org", "time.nist.gov", "time.google.com");
        }
        return;
    }

    portENTER_CRITICAL(&statusMux);
    status.wifi_connected = false;
    status.wifi_rssi = 0;
    snprintf(status.ip_address, sizeof(status.ip_address), "Offline");
    portEXIT_CRITICAL(&statusMux);

    if (static_cast<uint32_t>(now - lastReconnectAttemptMs) >= backoffMs) {
        lastReconnectAttemptMs = now;
        Serial.printf("[WiFi] STA disconnected (status=%d); retrying in %lu ms...\n",
                      static_cast<int>(currentStatus), static_cast<unsigned long>(backoffMs));
        WiFi.disconnect(false);
        WiFi.begin(activeSsid.c_str(), activePassword.c_str());
        backoffMs = (backoffMs * 2 <= WIFI_BACKOFF_MAX_MS) ? (backoffMs * 2) : WIFI_BACKOFF_MAX_MS;
    }
}

void WifiManager::handlePortalLoop(uint32_t now) {
    dnsServer.processNextRequest();
    webServer.handleClient();

    if (pendingRebootAfterSave && static_cast<uint32_t>(now - pendingRebootMs) >= 1000) {
        Serial.println("[WiFi] Rebooting after provisioning...");
        Serial.flush();
        ESP.restart();
    }

    if (!pendingRebootAfterSave &&
        static_cast<uint32_t>(now - portalStartedMs) >= WIFI_PORTAL_TIMEOUT_MS &&
        storageMgr.hasWifiCredentials()) {
        Serial.println("[WiFi] Provisioning portal timeout; resuming STA with saved credentials.");
        startSta();
    }
}

void WifiManager::loop() {
    bool openPortal = false;
    portENTER_CRITICAL(&statusMux);
    if (provisioningRequested) {
        provisioningRequested = false;
        openPortal = true;
    }
    portEXIT_CRITICAL(&statusMux);

    if (openPortal && mode != Mode::PROVISIONING) {
        startProvisioningPortal();
        return;
    }

    uint32_t now = millis();
    if (mode == Mode::PROVISIONING) {
        handlePortalLoop(now);
    } else {
        handleStaLoop(now);
    }
}

bool WifiManager::isConnected() {
    return mode == Mode::STA && WiFi.status() == WL_CONNECTED;
}

NetworkStatus WifiManager::getStatus() {
    NetworkStatus copy;
    portENTER_CRITICAL(&statusMux);
    copy = status;
    portEXIT_CRITICAL(&statusMux);
    return copy;
}
