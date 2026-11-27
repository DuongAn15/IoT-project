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
    bool takePendingMinuteLog(MinuteLogSample &out);

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

    // Sliding window of tip timestamps (ms) over RAIN_TIMEOUT_SEC (180s)
    uint32_t rainTipTimestamps[RAIN_RATE_WINDOW_MAX_TIPS];
    uint8_t rainTipHead;
    uint8_t rainTipWindowCount;
    void recordRainTipsInWindow(uint32_t nowMs, uint32_t count);
    uint8_t pruneAndCountRainTips(uint32_t nowMs);

    WeatherData currentData;
    portMUX_TYPE dataMux;

    // P04 v2 minute-log accumulator state
    uint32_t rainResetEpoch;
    uint32_t rainTipCounter;
    uint32_t minuteSequence;
    MinuteLogSample activeMinute;
    bool hasPendingMinute;
    MinuteLogSample pendingMinute;
    void resetActiveMinuteWindow(uint32_t nowMs);
    void finalizeActiveMinuteWindow(uint32_t nowMs);
};

extern SensorManager sensorMgr;

#endif // SENSOR_MANAGER_H

