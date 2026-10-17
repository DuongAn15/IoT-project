#include "oled_manager.h"

OledManager oledMgr;

OledManager::OledManager() 
    : display(128, 64, &Wire, -1),
      isAlertState(false),
      lastBlinkTime(0)
{}

void OledManager::begin() {
    Wire.begin(PIN_OLED_SDA, PIN_OLED_SCL);
    display.begin(OLED_I2C_ADDR, true);
    display.clearDisplay();
    display.setTextColor(SH110X_WHITE);
    display.display();
}

void OledManager::showBootScreen(const String &statusText) {
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
}

void OledManager::update(const WeatherData &weather, const NetworkStatus &net, const String &alertMessage) {
    display.clearDisplay();

    // 1. Header Bar
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.print("ADHT");

    // Network Status Badges
    display.setCursor(55, 0);
    if (net.wifi_connected) {
        display.print("W:OK");
    } else {
        display.print("W:--");
    }

    display.setCursor(95, 0);
    if (net.mqtt_connected) {
        display.print("M:OK");
    } else {
        display.print("M:--");
    }

    display.drawFastHLine(0, 10, 128, SH110X_WHITE);

    // 2. Weather Grid (2x2 layout)
    // Left: Temperature & Humidity
    display.setCursor(0, 14);
    display.print("T: ");
    display.setTextSize(1);
    display.printf("%.1f C", weather.temperature);

    display.setCursor(0, 26);
    display.print("H: ");
    display.printf("%.1f %%", weather.humidity);

    // Right: Wind & Rain
    display.setCursor(68, 14);
    display.print("W: ");
    display.printf("%.1f", weather.wind_speed);
    display.setCursor(106, 14);
    display.print("m/s");

    display.setCursor(68, 26);
    display.print("R: ");
    display.printf("%.1f", weather.rain_rate);
    display.setCursor(106, 26);
    display.print("mm");

    display.drawFastHLine(0, 38, 128, SH110X_WHITE);

    // 3. Footer / Alerts
    display.setCursor(0, 42);
    if (alertMessage.length() > 0) {
        display.print("! ");
        display.print(alertMessage);
    } else {
        display.print("IP: ");
        display.print(net.ip_address);
    }

    display.setCursor(0, 54);
    display.printf("Total Rain: %.1f mm", weather.rain_total);

    display.display();
}

