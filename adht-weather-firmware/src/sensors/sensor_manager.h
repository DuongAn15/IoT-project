#ifndef SENSOR_MANAGER_H
#define SENSOR_MANAGER_H

#include "../config.h"
#include "../types.h"
#include <DHT.h>
#include <SimpleKalmanFilter.h>

class SensorManager {
public:
    SensorManager();
    void begin();
    void update();
    WeatherData getData();
    void resetRainTotal();

    // ISR handlers (called from static ISR wrapper)
    void handleRainInterrupt();
    void handleWindInterrupt();

private:
    DHT dht;
    SimpleKalmanFilter tempFilter;
    SimpleKalmanFilter humiFilter;
    bool kalmanSeeded;

    portMUX_TYPE isrMux;
    volatile uint32_t rainPulseCount;
    volatile uint32_t windPulseCount;
    volatile uint32_t lastRainDebounce;
    volatile uint32_t lastWindDebounce;

    // Calculation variables
    float mmPerPulse;
    float circumferenceWind;

    uint32_t lastRainCalcTime;
    uint32_t lastWindCalcTime;
    uint32_t lastDhtReadTime;
    uint32_t lastValidDhtTime;

    // Wind Gust sliding window (10 minutes = 120 samples x 5 seconds)
    float windGustHistory[WIND_GUST_WINDOW_SAMPLES];
    uint16_t windGustIndex;
    uint16_t windGustCount;

    // Fast rain rate calculation with instant delta-t & decay
    uint32_t lastRainTipTime;
    float lastRainRateCalculated;

    WeatherData currentData;
    portMUX_TYPE dataMux;
};

extern SensorManager sensorMgr;

#endif // SENSOR_MANAGER_H

