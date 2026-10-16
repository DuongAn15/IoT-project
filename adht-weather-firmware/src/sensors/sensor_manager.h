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

    // ISR handlers (called from static ISR wrapper)
    void handleRainInterrupt();
    void handleWindInterrupt();

private:
    DHT dht;
    SimpleKalmanFilter tempFilter;
    SimpleKalmanFilter humiFilter;

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

    WeatherData currentData;
    portMUX_TYPE dataMux;
};

extern SensorManager sensorMgr;

#endif // SENSOR_MANAGER_H

