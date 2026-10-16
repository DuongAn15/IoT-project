#include "sensor_manager.h"

SensorManager sensorMgr;

// Static ISR wrappers
void IRAM_ATTR isrRainPulse() {
    sensorMgr.handleRainInterrupt();
}

void IRAM_ATTR isrWindPulse() {
    sensorMgr.handleWindInterrupt();
}

SensorManager::SensorManager() 
    : dht(PIN_DHT11, DHT11),
      tempFilter(2, 2, 0.001),
      humiFilter(2, 2, 0.001),
      rainPulseCount(0),
      windPulseCount(0),
      lastRainDebounce(0),
      lastWindDebounce(0),
      lastRainCalcTime(0),
      lastWindCalcTime(0),
      lastDhtReadTime(0)
{
    isrMux = portMUX_INITIALIZER_UNLOCKED;
    dataMux = portMUX_INITIALIZER_UNLOCKED;
}

void SensorManager::begin() {
    dht.begin();

    // 1 pulse mm calculation: (1000000 / Area_mm2) * Volume_ml / 1000 = mm
    mmPerPulse = ((1000000.0f / RAIN_FUNNEL_AREA_MM2) * RAIN_BUCKET_ML) / 1000.0f;

    // Wind circumference: C = PI * D
    float d_meters = WIND_ANEMOMETER_D_MM / 1000.0f;
    circumferenceWind = 3.14159265f * d_meters;

    pinMode(PIN_RAIN_SENSOR, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(PIN_RAIN_SENSOR), isrRainPulse, FALLING);

    pinMode(PIN_WIND_SENSOR, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(PIN_WIND_SENSOR), isrWindPulse, FALLING);

    lastRainCalcTime = millis();
    lastWindCalcTime = millis();
    lastDhtReadTime = millis();
}

void SensorManager::handleRainInterrupt() {
    uint32_t now = millis();
    if (now - lastRainDebounce > 150) { // 150ms debounce
        portENTER_CRITICAL_ISR(&isrMux);
        rainPulseCount++;
        portEXIT_CRITICAL_ISR(&isrMux);
        lastRainDebounce = now;
    }
}

void SensorManager::handleWindInterrupt() {
    uint32_t now = millis();
    if (now - lastWindDebounce > 50) { // 50ms debounce
        portENTER_CRITICAL_ISR(&isrMux);
        windPulseCount++;
        portEXIT_CRITICAL_ISR(&isrMux);
        lastWindDebounce = now;
    }
}

void SensorManager::update() {
    uint32_t now = millis();

    // 1. Read DHT11 every SENSOR_READ_INTERVAL_MS
    if (now - lastDhtReadTime >= SENSOR_READ_INTERVAL_MS) {
        lastDhtReadTime = now;
        float rawTemp = dht.readTemperature();
        float rawHumi = dht.readHumidity();

        if (!isnan(rawTemp) && !isnan(rawHumi)) {
            float filteredTemp = tempFilter.updateEstimate(rawTemp);
            float filteredHumi = humiFilter.updateEstimate(rawHumi);

            portENTER_CRITICAL(&dataMux);
            currentData.temperature = filteredTemp;
            currentData.humidity = filteredHumi;
            currentData.last_updated = now;
            portEXIT_CRITICAL(&dataMux);
        }
    }

    // 2. Calculate Wind Speed every WIND_SAMPLE_PERIOD_SEC
    if (now - lastWindCalcTime >= (WIND_SAMPLE_PERIOD_SEC * 1000)) {
        float elapsedSec = (now - lastWindCalcTime) / 1000.0f;
        lastWindCalcTime = now;

        uint32_t pulses = 0;
        portENTER_CRITICAL(&isrMux);
        pulses = windPulseCount;
        windPulseCount = 0;
        portEXIT_CRITICAL(&isrMux);

        // Distance = pulses * circumference; Speed = distance / time
        float speed = (pulses * circumferenceWind) / elapsedSec;

        portENTER_CRITICAL(&dataMux);
        currentData.wind_speed = speed;
        if (speed > currentData.wind_max) {
            currentData.wind_max = speed;
        }
        portEXIT_CRITICAL(&dataMux);
    }

    // 3. Calculate Rain Rate every RAIN_SAMPLE_PERIOD_SEC
    if (now - lastRainCalcTime >= (RAIN_SAMPLE_PERIOD_SEC * 1000)) {
        float elapsedSec = (now - lastRainCalcTime) / 1000.0f;
        lastRainCalcTime = now;

        uint32_t pulses = 0;
        portENTER_CRITICAL(&isrMux);
        pulses = rainPulseCount;
        rainPulseCount = 0;
        portEXIT_CRITICAL(&isrMux);

        float mmInPeriod = pulses * mmPerPulse;
        // Rate in mm/hour: mmInPeriod * (3600 / elapsedSec)
        float rate = mmInPeriod * (3600.0f / elapsedSec);

        portENTER_CRITICAL(&dataMux);
        currentData.rain_rate = rate;
        currentData.rain_total += mmInPeriod;
        portEXIT_CRITICAL(&dataMux);
    }
}

WeatherData SensorManager::getData() {
    WeatherData copy;
    portENTER_CRITICAL(&dataMux);
    copy = currentData;
    portEXIT_CRITICAL(&dataMux);
    return copy;
}

