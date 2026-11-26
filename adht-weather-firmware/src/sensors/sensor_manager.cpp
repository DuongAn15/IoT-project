#include "sensor_manager.h"
#include <esp_timer.h>
#include <time.h>

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
      lastValidDhtTime(0),
      windGustIndex(0),
      windGustCount(0),
      lastRainTipTime(0),
      lastRainRateCalculated(0.0f),
      rainResetEpoch(0),
      rainTipCounter(0),
      minuteSequence(0),
      hasPendingMinute(false)
{
    isrMux = portMUX_INITIALIZER_UNLOCKED;
    dataMux = portMUX_INITIALIZER_UNLOCKED;
    memset(windGustHistory, 0, sizeof(windGustHistory));
}

void SensorManager::begin() {
    dht.begin();

    // 1 pulse mm calculation: (1000000 / Area_mm2) * Volume_ml / 1000 = mm
    mmPerPulse = ((1000000.0f / RAIN_FUNNEL_AREA_MM2) * RAIN_BUCKET_ML) / 1000.0f;

    // Wind circumference: C = PI * D
    float d_meters = WIND_ANEMOMETER_D_MM / 1000.0f;
    circumferenceWind = 3.14159265f * d_meters;

    windGustIndex = 0;
    windGustCount = 0;
    memset(windGustHistory, 0, sizeof(windGustHistory));
    lastRainTipTime = 0;
    lastRainRateCalculated = 0.0f;

    pinMode(PIN_RAIN_SENSOR, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(PIN_RAIN_SENSOR), isrRainPulse, FALLING);

    pinMode(PIN_WIND_SENSOR, INPUT_PULLUP);
    attachInterrupt(digitalPinToInterrupt(PIN_WIND_SENSOR), isrWindPulse, FALLING);

    uint32_t now = millis();
    lastRainCalcTime = now;
    lastWindCalcTime = now;
    lastDhtReadTime = now - SENSOR_READ_INTERVAL_MS;
    lastValidDhtTime = now;
    resetActiveMinuteWindow(now);
}

void SensorManager::resetActiveMinuteWindow(uint32_t nowMs) {
    activeMinute = MinuteLogSample();
    activeMinute.uptime_start_ms = nowMs;
    activeMinute.epoch_start_sec = static_cast<int64_t>(time(nullptr));
    activeMinute.rain_reset_epoch = rainResetEpoch;
    activeMinute.tip_count_start = rainTipCounter;
    activeMinute.tip_count_end = rainTipCounter;
}

void SensorManager::finalizeActiveMinuteWindow(uint32_t nowMs) {
    activeMinute.uptime_end_ms = nowMs;
    activeMinute.epoch_end_sec = static_cast<int64_t>(time(nullptr));
    activeMinute.clock_synchronized =
        (activeMinute.epoch_start_sec >= 1700000000LL &&
         activeMinute.epoch_end_sec > activeMinute.epoch_start_sec);
    activeMinute.window_sequence = ++minuteSequence;
    activeMinute.tip_count_end = rainTipCounter;

    portENTER_CRITICAL(&dataMux);
    pendingMinute = activeMinute;
    hasPendingMinute = true;
    portEXIT_CRITICAL(&dataMux);

    resetActiveMinuteWindow(nowMs);
}

bool SensorManager::takePendingMinuteLog(MinuteLogSample &out) {
    bool found = false;
    portENTER_CRITICAL(&dataMux);
    if (hasPendingMinute) {
        out = pendingMinute;
        hasPendingMinute = false;
        found = true;
    }
    portEXIT_CRITICAL(&dataMux);
    return found;
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
        activeMinute.dht_expected_count++;
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

            if (activeMinute.dht_valid_count == 0) {
                activeMinute.temp_min = filteredTemp;
                activeMinute.temp_max = filteredTemp;
                activeMinute.humi_min = filteredHumi;
                activeMinute.humi_max = filteredHumi;
            } else {
                if (filteredTemp < activeMinute.temp_min) activeMinute.temp_min = filteredTemp;
                if (filteredTemp > activeMinute.temp_max) activeMinute.temp_max = filteredTemp;
                if (filteredHumi < activeMinute.humi_min) activeMinute.humi_min = filteredHumi;
                if (filteredHumi > activeMinute.humi_max) activeMinute.humi_max = filteredHumi;
            }
            activeMinute.temp_sum += filteredTemp;
            activeMinute.temp_latest = filteredTemp;
            activeMinute.humi_sum += filteredHumi;
            activeMinute.humi_latest = filteredHumi;
            activeMinute.dht_valid_count++;

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

    // 2. Calculate Wind Speed every WIND_SAMPLE_PERIOD_SEC (5s)
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

        activeMinute.wind_expected_count++;
        if (activeMinute.wind_valid_count == 0) {
            activeMinute.wind_min = speed;
            activeMinute.wind_max = speed;
        } else {
            if (speed < activeMinute.wind_min) activeMinute.wind_min = speed;
            if (speed > activeMinute.wind_max) activeMinute.wind_max = speed;
        }
        activeMinute.wind_sum += speed;
        activeMinute.wind_latest = speed;
        activeMinute.wind_valid_count++;

        // Push into 10-minute sliding window ring buffer (120 samples x 5s = 600s)
        windGustHistory[windGustIndex] = speed;
        windGustIndex = (windGustIndex + 1) % WIND_GUST_WINDOW_SAMPLES;
        if (windGustCount < WIND_GUST_WINDOW_SAMPLES) {
            windGustCount++;
        }

        // Calculate peak gust in the 10-minute window
        float maxGust = speed;
        for (uint16_t i = 0; i < windGustCount; i++) {
            if (windGustHistory[i] > maxGust) {
                maxGust = windGustHistory[i];
            }
        }

        portENTER_CRITICAL(&dataMux);
        currentData.wind_speed = speed;
        currentData.wind_max = maxGust;
        portEXIT_CRITICAL(&dataMux);
    }

    // 3. Fast Rain Rate calculation (instant delta-t) & Continuous Accumulation
    uint32_t rainPulses = 0;
    portENTER_CRITICAL(&isrMux);
    rainPulses = rainPulseCount;
    rainPulseCount = 0;
    portEXIT_CRITICAL(&isrMux);

    if (rainPulses > 0) {
        rainTipCounter += rainPulses;
        activeMinute.tip_count_end = rainTipCounter;
        float mmAdded = rainPulses * mmPerPulse;

        portENTER_CRITICAL(&dataMux);
        currentData.rain_total += mmAdded;
        portEXIT_CRITICAL(&dataMux);

        if (lastRainTipTime > 0) {
            float deltaSec = (now - lastRainTipTime) / 1000.0f;
            if (deltaSec > 0.0f && deltaSec <= RAIN_TIMEOUT_SEC) {
                lastRainRateCalculated = mmAdded * (3600.0f / deltaSec);
            } else {
                lastRainRateCalculated = mmAdded * (3600.0f / static_cast<float>(RAIN_TIMEOUT_SEC));
            }
        } else {
            lastRainRateCalculated = mmAdded * (3600.0f / static_cast<float>(RAIN_TIMEOUT_SEC));
        }
        lastRainTipTime = now;

        portENTER_CRITICAL(&dataMux);
        currentData.rain_rate = lastRainRateCalculated;
        portEXIT_CRITICAL(&dataMux);
    } else if (lastRainTipTime > 0) {
        // No pulse in this tick: apply decay or timeout
        float idleSec = (now - lastRainTipTime) / 1000.0f;
        if (idleSec >= RAIN_TIMEOUT_SEC) {
            lastRainRateCalculated = 0.0f;
            portENTER_CRITICAL(&dataMux);
            currentData.rain_rate = 0.0f;
            portEXIT_CRITICAL(&dataMux);
        } else if (lastRainRateCalculated > 0.0f) {
            float decayRate = mmPerPulse * (3600.0f / idleSec);
            if (decayRate < lastRainRateCalculated) {
                lastRainRateCalculated = decayRate;
                portENTER_CRITICAL(&dataMux);
                currentData.rain_rate = lastRainRateCalculated;
                portEXIT_CRITICAL(&dataMux);
            }
        }
    }

    // 4. Close 60-second minute-log window for v2 pipeline
    if (static_cast<uint32_t>(now - activeMinute.uptime_start_ms) >= (RAIN_SAMPLE_PERIOD_SEC * 1000UL)) {
        finalizeActiveMinuteWindow(now);
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
    uint32_t now = millis();
    if (static_cast<uint32_t>(now - activeMinute.uptime_start_ms) >= 1000UL) {
        finalizeActiveMinuteWindow(now);
    }

    portENTER_CRITICAL(&isrMux);
    rainPulseCount = 0;
    portEXIT_CRITICAL(&isrMux);

    rainResetEpoch++;
    rainTipCounter = 0;
    resetActiveMinuteWindow(now);

    lastRainTipTime = 0;
    lastRainRateCalculated = 0.0f;

    portENTER_CRITICAL(&dataMux);
    currentData.rain_rate = 0.0f;
    currentData.rain_total = 0.0f;
    portEXIT_CRITICAL(&dataMux);
}

