#include "oled_manager.h"

OledManager oledMgr;

OledManager::OledManager() 
    : display(128, 64, &Wire, -1),
      oledReady(false),
      isAlertState(false),
      lastBlinkTime(0),
      currentPage(PAGE_OVERVIEW),
      lastActivityMs(0),
      screenSaverActive(false)
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
}

void OledManager::wakeScreen() {
    portENTER_CRITICAL(&oledMux);
    lastActivityMs = millis();
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
    portEXIT_CRITICAL(&oledMux);
    wakeScreen();
}

void OledManager::setPage(uint8_t page) {
    portENTER_CRITICAL(&oledMux);
    currentPage = page % PAGE_COUNT;
    lastActivityMs = millis();
    portEXIT_CRITICAL(&oledMux);
    wakeScreen();
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

void OledManager::update(const WeatherData &weather, const NetworkStatus &net, const char *alertMessage) {
    if (!oledReady) return;

    uint32_t now = millis();

    // If there is an active alert condition, wake screen immediately
    if (alertMessage != nullptr && alertMessage[0] != '\0') {
        wakeScreen();
    }

    portENTER_CRITICAL(&oledMux);
    uint32_t lastAct = lastActivityMs;
    bool isOff = screenSaverActive;
    uint8_t page = currentPage;
    portEXIT_CRITICAL(&oledMux);

    // Screen saver check: auto turn off after SCREEN_SAVER_TIMEOUT_MS
    if (!isOff && (static_cast<uint32_t>(now - lastAct) >= SCREEN_SAVER_TIMEOUT_MS)) {
        display.oled_command(SH110X_DISPLAYOFF);
        portENTER_CRITICAL(&oledMux);
        screenSaverActive = true;
        portEXIT_CRITICAL(&oledMux);
        return;
    }

    if (isOff) {
        return; // Don't draw while screen saver is active (saves I2C traffic & CPU)
    }

    display.clearDisplay();

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

    display.display();
}

