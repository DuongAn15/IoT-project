#include "oled_manager.h"

OledManager oledMgr;

OledManager::OledManager() 
    : display(128, 64, &Wire, -1),
      oledReady(false),
      isAlertState(false),
      lastBlinkTime(0),
      currentPage(PAGE_OVERVIEW),
      lastActivityMs(0),
      screenSaverActive(false),
      lastPeriodicWakeMs(0),
      isPeriodicTourActive(false),
      tourStartMs(0),
      lastPageRotateMs(0)
{
    oledMux = portMUX_INITIALIZER_UNLOCKED;
}

void OledManager::begin() {
    Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);
    Wire.setTimeOut(50);
    oledReady = display.begin(OLED_I2C_ADDR, true);
    if (!oledReady) {
        Serial.println("[OLED] Display initialization failed (check I2C wiring)");
        return;
    }
    display.clearDisplay();
    display.setTextColor(SH110X_WHITE);
    display.display();
    lastActivityMs = millis();
    lastPeriodicWakeMs = millis();
    isPeriodicTourActive = false;
}

void OledManager::showBootScreen(const String &statusText) {
    if (!oledReady) return;
    display.clearDisplay();
    display.setTextSize(1);
    display.setCursor(18, 10);
    display.println("ADHT WEATHER");
    display.setCursor(22, 22);
    display.println("STATION V2.0");
    display.drawFastHLine(10, 36, 108, SH110X_WHITE);
    display.setCursor(10, 44);
    display.println(statusText);
    display.display();
    lastActivityMs = millis();
    lastPeriodicWakeMs = millis();
}

void OledManager::wakeScreen() {
    portENTER_CRITICAL(&oledMux);
    lastActivityMs = millis();
    isPeriodicTourActive = false; // Manual interaction cancels periodic tour
    bool needTurnOn = screenSaverActive;
    screenSaverActive = false;
    portEXIT_CRITICAL(&oledMux);

    if (needTurnOn && oledReady) {
        display.oled_command(SH110X_DISPLAYON);
    }
}

void OledManager::nextPage() {
    portENTER_CRITICAL(&oledMux);
    currentPage = (currentPage + 1) % PAGE_COUNT;
    lastActivityMs = millis();
    isPeriodicTourActive = false; // Manual page switch cancels tour and gives full 2 min
    bool needTurnOn = screenSaverActive;
    screenSaverActive = false;
    portEXIT_CRITICAL(&oledMux);

    if (needTurnOn && oledReady) {
        display.oled_command(SH110X_DISPLAYON);
    }
}

void OledManager::nextPageClamped() {
    portENTER_CRITICAL(&oledMux);
    if (currentPage + 1 < PAGE_COUNT) {
        currentPage++;
    }
    lastActivityMs = millis();
    isPeriodicTourActive = false;
    bool needTurnOn = screenSaverActive;
    screenSaverActive = false;
    portEXIT_CRITICAL(&oledMux);

    if (needTurnOn && oledReady) {
        display.oled_command(SH110X_DISPLAYON);
    }
}

void OledManager::prevPage() {
    portENTER_CRITICAL(&oledMux);
    if (currentPage > 0) {
        currentPage--;
    }
    lastActivityMs = millis();
    isPeriodicTourActive = false;
    bool needTurnOn = screenSaverActive;
    screenSaverActive = false;
    portEXIT_CRITICAL(&oledMux);

    if (needTurnOn && oledReady) {
        display.oled_command(SH110X_DISPLAYON);
    }
}

void OledManager::setPage(uint8_t page) {
    portENTER_CRITICAL(&oledMux);
    currentPage = page % PAGE_COUNT;
    lastActivityMs = millis();
    isPeriodicTourActive = false;
    bool needTurnOn = screenSaverActive;
    screenSaverActive = false;
    portEXIT_CRITICAL(&oledMux);

    if (needTurnOn && oledReady) {
        display.oled_command(SH110X_DISPLAYON);
    }
}

uint8_t OledManager::getPage() {
    portENTER_CRITICAL(&oledMux);
    uint8_t page = currentPage;
    portEXIT_CRITICAL(&oledMux);
    return page;
}

void OledManager::renderPageOverview(const WeatherData &weather, const NetworkStatus &net, const char *alertMessage) {
    // 1. Header Bar
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.print("ADHT");

    display.setCursor(42, 0);
    display.print(net.wifi_connected ? "W:OK" : "W:--");

    display.setCursor(76, 0);
    display.print(net.mqtt_connected ? "M:OK" : "M:--");

    display.setCursor(110, 0);
    display.print("1/3");

    display.drawFastHLine(0, 10, 128, SH110X_WHITE);

    // 2. Weather Grid (2x2 layout)
    // Left: Temperature & Humidity
    display.setCursor(0, 14);
    display.print("T: ");
    if (!weather.dht_ok) {
        display.print("ERR");
    } else {
        display.printf("%.1f C", weather.temperature);
    }

    display.setCursor(0, 26);
    display.print("H: ");
    if (!weather.dht_ok) {
        display.print("ERR");
    } else {
        display.printf("%.1f %%", weather.humidity);
    }

    // Right: Wind & Rain Rate (with correct mm/h unit)
    display.setCursor(64, 14);
    display.printf("W:%.1f", weather.wind_speed);
    display.setCursor(106, 14);
    display.print("m/s");

    display.setCursor(64, 26);
    display.printf("R:%.1f", weather.rain_rate);
    display.setCursor(102, 26);
    display.print("mm/h");

    display.drawFastHLine(0, 38, 128, SH110X_WHITE);

    // 3. Footer / Alerts & Rain Total
    display.setCursor(0, 42);
    if (alertMessage != nullptr && alertMessage[0] != '\0') {
        display.print("! ");
        display.print(alertMessage);
    } else if (!weather.dht_ok) {
        display.print("! DHT11 SENSOR ERR");
    } else {
        display.print("IP: ");
        display.print(net.ip_address);
    }

    display.setCursor(0, 54);
    display.printf("Rain Tot: %.1f mm", weather.rain_total);
}

void OledManager::renderPageExtremes(const WeatherData &weather, const char *alertMessage) {
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.print("CLIMATE & PEAKS");
    display.setCursor(110, 0);
    display.print("2/3");
    display.drawFastHLine(0, 10, 128, SH110X_WHITE);

    display.setCursor(0, 14);
    display.printf("Wind Gust: %.1f m/s", weather.wind_max);
    display.setCursor(0, 24);
    display.print("(10-min peak window)");

    display.setCursor(0, 36);
    display.printf("Rain Rate: %.1f mm/h", weather.rain_rate);

    display.setCursor(0, 46);
    display.printf("Rain Tot : %.1f mm", weather.rain_total);

    display.setCursor(0, 56);
    if (alertMessage != nullptr && alertMessage[0] != '\0') {
        display.print("! ");
        display.print(alertMessage);
    } else {
        display.printf("DHT: %s", weather.dht_ok ? "HEALTHY" : "ERROR");
    }
}

void OledManager::renderPageSystem(const WeatherData &weather, const NetworkStatus &net) {
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.print("SYSTEM & NETWORK");
    display.setCursor(110, 0);
    display.print("3/3");
    display.drawFastHLine(0, 10, 128, SH110X_WHITE);

    display.setCursor(0, 14);
    display.printf("WiFi: %s (%d dBm)", net.wifi_connected ? "OK" : "DISC", net.wifi_rssi);

    display.setCursor(0, 25);
    display.printf("IP  : %s", net.ip_address);

    display.setCursor(0, 36);
    display.printf("MQTT: %s", net.mqtt_connected ? "CONNECTED" : "OFFLINE");

    display.setCursor(0, 47);
    display.printf("Node: %s", DEVICE_ID);

    display.setCursor(0, 56);
    uint32_t uptimeSec = millis() / 1000;
    display.printf("Uptime: %lu s", static_cast<unsigned long>(uptimeSec));
}

void OledManager::renderProvisioningScreen(const NetworkStatus &net) {
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.print("WIFI SETUP PORTAL");
    display.drawFastHLine(0, 10, 128, SH110X_WHITE);

    display.setCursor(0, 15);
    display.print("SSID:");
    display.setCursor(0, 24);
    display.print(net.ap_ssid);

    display.setCursor(0, 35);
    display.print("PASS:");
    display.setCursor(34, 35);
    display.print(net.ap_pass);

    display.drawFastHLine(0, 47, 128, SH110X_WHITE);
    display.setCursor(0, 52);
    display.print(net.ap_url);
}

void OledManager::update(const WeatherData &weather, const NetworkStatus &net, const char *alertMessage) {
    if (!oledReady) return;

    uint32_t now = millis();

    // 1. If there is an active alert condition, wake screen immediately and keep awake
    if (alertMessage != nullptr && alertMessage[0] != '\0') {
        wakeScreen();
    }

    portENTER_CRITICAL(&oledMux);
    bool isOff = screenSaverActive;
    bool isTour = isPeriodicTourActive;
    uint32_t tourStart = tourStartMs;
    uint32_t lastTourWake = lastPeriodicWakeMs;
    uint32_t lastAct = lastActivityMs;
    uint32_t lastRotate = lastPageRotateMs;
    uint8_t page = currentPage;
    portEXIT_CRITICAL(&oledMux);

    // 2. Periodic Wakeup Check (When screen is currently asleep)
    if (isOff) {
        if (static_cast<uint32_t>(now - lastTourWake) >= OLED_PERIODIC_WAKE_INTERVAL_MS) {
            // 10 minutes elapsed: Wake up for 30s auto-tour!
            display.oled_command(SH110X_DISPLAYON);

            portENTER_CRITICAL(&oledMux);
            screenSaverActive = false;
            isPeriodicTourActive = true;
            tourStartMs = now;
            lastPeriodicWakeMs = now;
            lastPageRotateMs = now;
            currentPage = PAGE_OVERVIEW;
            isOff = false;
            isTour = true;
            page = PAGE_OVERVIEW;
            portEXIT_CRITICAL(&oledMux);
        } else {
            return; // Still sleeping: save I2C traffic and CPU
        }
    }

    // 3. Screen is ON: handle sleep timers and tour rotation
    if (isTour) {
        // Tour mode: runs for exactly 30 seconds
        if (static_cast<uint32_t>(now - tourStart) >= OLED_PERIODIC_WAKE_DURATION_MS) {
            // Tour finished -> turn screen back off to sleep
            display.oled_command(SH110X_DISPLAYOFF);

            portENTER_CRITICAL(&oledMux);
            screenSaverActive = true;
            isPeriodicTourActive = false;
            lastPeriodicWakeMs = now; // Count 10 minutes from when screen turns off
            portEXIT_CRITICAL(&oledMux);
            return;
        }

        // Auto-rotate page every 10 seconds during the 30s tour (Page 1 -> Page 2 -> Page 3)
        if (static_cast<uint32_t>(now - lastRotate) >= OLED_PAGE_ROTATE_INTERVAL_MS) {
            portENTER_CRITICAL(&oledMux);
            currentPage = (currentPage + 1) % PAGE_COUNT;
            lastPageRotateMs = now;
            page = currentPage;
            portEXIT_CRITICAL(&oledMux);
        }
    } else {
        // Manual mode: stays awake for 2 minutes from last button press or alert
        if (static_cast<uint32_t>(now - lastAct) >= SCREEN_SAVER_TIMEOUT_MS) {
            display.oled_command(SH110X_DISPLAYOFF);

            portENTER_CRITICAL(&oledMux);
            screenSaverActive = true;
            lastPeriodicWakeMs = now; // Count 10 minutes from when screen turns off
            portEXIT_CRITICAL(&oledMux);
            return;
        }
    }

    // 4. Render active page
    display.clearDisplay();

    if (net.provisioning_active) {
        renderProvisioningScreen(net);
    } else {
        switch (page) {
            case PAGE_EXTREMES:
                renderPageExtremes(weather, alertMessage);
                break;
            case PAGE_SYSTEM:
                renderPageSystem(weather, net);
                break;
            case PAGE_OVERVIEW:
            default:
                renderPageOverview(weather, net, alertMessage);
                break;
        }
    }

    display.display();
}

