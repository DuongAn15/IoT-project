#include "sensor_manager.h"
#include <esp_timer.h>

SensorManager sensorMgr;

// Static ISR wrappers (must stay in IRAM)
void IRAM_ATTR isrRainPulse() {
    sensorMgr.handleRainInterrupt();
}

void IRAM_ATTR isrWindPulse() {
    sensorMgr.handleWindInterrupt();
}

SensorManager::SensorManager() 
    : dht(PIN_DHT11, DHT11),
      tempFilter(2.0f, 2.0f, 0.04f),
      humiFilter(2.0f, 2.0f, 0.04f),
      kalmanSeeded(false),
      rainPulseCount(0),
      windPulseCount(0),
      lastRainDebounce(0),
      lastWindDebounce(0),
      mmPerPulse(0.0f),
      circumferenceWind(0.0f),
      lastRainCalcTime(0),
      lastWindCalcTime(0),
      lastDhtReadTime(0),
      lastValidDhtTime(0)
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

    uint32_t now = millis();
    lastRainCalcTime = now;
    lastWindCalcTime = now;
    lastDhtReadTime = now - SENSOR_READ_INTERVAL_MS;
    lastValidDhtTime = now;
}

void IRAM_ATTR SensorManager::handleRainInterrupt() {
    portENTER_CRITICAL_ISR(&isrMux);
    uint32_t now = static_cast<uint32_t>(esp_timer_get_time() / 1000ULL);
    if (static_cast<uint32_t>(now - lastRainDebounce) >= RAIN_DEBOUNCE_MS) {
        rainPulseCount = rainPulseCount + 1;
        lastRainDebounce = now;
    }
    portEXIT_CRITICAL_ISR(&isrMux);
}

void IRAM_ATTR SensorManager::handleWindInterrupt() {
    portENTER_CRITICAL_ISR(&isrMux);
    uint32_t now = static_cast<uint32_t>(esp_timer_get_time() / 1000ULL);
    if (static_cast<uint32_t>(now - lastWindDebounce) >= WIND_DEBOUNCE_MS) {
        windPulseCount = windPulseCount + 1;
        lastWindDebounce = now;
    }
    portEXIT_CRITICAL_ISR(&isrMux);
}

void SensorManager::update() {
    uint32_t now = millis();

    // 1. Read DHT11 every SENSOR_READ_INTERVAL_MS (2500ms >= MIN_INTERVAL 2000ms)
    if (static_cast<uint32_t>(now - lastDhtReadTime) >= SENSOR_READ_INTERVAL_MS) {
        lastDhtReadTime = now;
        float rawTemp = dht.readTemperature();
        float rawHumi = dht.readHumidity();

        if (!isnan(rawTemp) && !isnan(rawHumi)) {
            if (!kalmanSeeded) {
                // Prime initial estimate error so sample 1 snaps straight to real ambient value
                tempFilter.setEstimateError(10000.0f);
                humiFilter.setEstimateError(10000.0f);
            }

            float filteredTemp = tempFilter.updateEstimate(rawTemp);
            float filteredHumi = humiFilter.updateEstimate(rawHumi);

            if (!kalmanSeeded) {
                tempFilter.setEstimateError(2.0f);
                humiFilter.setEstimateError(2.0f);
                kalmanSeeded = true;
            }

            // Clamp within Backend CreateTelemetryDto valid bounds
            if (filteredTemp < -40.0f) filteredTemp = -40.0f;
            if (filteredTemp > 80.0f) filteredTemp = 80.0f;
            if (filteredHumi < 0.0f) filteredHumi = 0.0f;
            if (filteredHumi > 100.0f) filteredHumi = 100.0f;

            lastValidDhtTime = now;

            portENTER_CRITICAL(&dataMux);
            currentData.temperature = filteredTemp;
            currentData.humidity = filteredHumi;
            currentData.last_updated = now;
            currentData.dht_ok = true;
            currentData.has_valid_dht = true;
            portEXIT_CRITICAL(&dataMux);
        } else if (static_cast<uint32_t>(now - lastValidDhtTime) >= DHT_ERROR_TIMEOUT_MS) {
            portENTER_CRITICAL(&dataMux);
            currentData.dht_ok = false;
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

void SensorManager::resetRainTotal() {
    portENTER_CRITICAL(&isrMux);
    rainPulseCount = 0;
    portEXIT_CRITICAL(&isrMux);

    portENTER_CRITICAL(&dataMux);
    currentData.rain_rate = 0.0f;
    currentData.rain_total = 0.0f;
    portEXIT_CRITICAL(&dataMux);
}

