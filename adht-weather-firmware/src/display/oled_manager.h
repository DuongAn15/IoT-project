#ifndef OLED_MANAGER_H
#define OLED_MANAGER_H

#include "../config.h"
#include "../types.h"
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h>

class OledManager {
public:
    OledManager();
    void begin();
    void update(const WeatherData &weather, const NetworkStatus &net, const String &alertMessage = "");
    void showBootScreen(const String &statusText);

private:
    Adafruit_SH1106G display;
    bool isAlertState;
    uint32_t lastBlinkTime;
};

extern OledManager oledMgr;

#endif // OLED_MANAGER_H

