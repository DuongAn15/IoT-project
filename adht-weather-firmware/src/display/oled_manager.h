#ifndef OLED_MANAGER_H
#define OLED_MANAGER_H

#include "../config.h"
#include "../types.h"
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h>

enum OledPage {
    PAGE_OVERVIEW = 0,
    PAGE_EXTREMES = 1,
    PAGE_SYSTEM = 2,
    PAGE_COUNT = 3
};

class OledManager {
public:
    OledManager();
    void begin();
    void update(const WeatherData &weather, const NetworkStatus &net, const char *alertMessage = "");
    void showBootScreen(const String &statusText);
    void nextPage();
    void setPage(uint8_t page);
    uint8_t getPage();
    void wakeScreen();

private:
    void renderPageOverview(const WeatherData &weather, const NetworkStatus &net, const char *alertMessage);
    void renderPageExtremes(const WeatherData &weather, const char *alertMessage);
    void renderPageSystem(const WeatherData &weather, const NetworkStatus &net);

    Adafruit_SH1106G display;
    bool oledReady;
    bool isAlertState;
    uint32_t lastBlinkTime;

    portMUX_TYPE oledMux;
    uint8_t currentPage;
    uint32_t lastActivityMs;
    bool screenSaverActive;

    // Periodic 10-minute auto-tour parameters
    uint32_t lastPeriodicWakeMs;
    bool isPeriodicTourActive;
    uint32_t tourStartMs;
    uint32_t lastPageRotateMs;
};

extern OledManager oledMgr;

#endif // OLED_MANAGER_H

