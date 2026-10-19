#include "supabase_manager.h"
#include <ArduinoJson.h>

SupabaseManager supabaseMgr;

SupabaseManager::SupabaseManager() {}

void SupabaseManager::begin() {
    secureClient.setInsecure();
    endpointUrl = String(SUPABASE_URL) + "/rest/v1/" + String(SUPABASE_TABLE);
}

bool SupabaseManager::logWeatherData(const WeatherData &data) {
    if (WiFi.status() != WL_CONNECTED) {
        return false;
    }

    HTTPClient http;
    http.begin(secureClient, endpointUrl);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("apikey", SUPABASE_ANON_KEY);
    http.addHeader("Authorization", String("Bearer ") + SUPABASE_ANON_KEY);
    http.addHeader("Prefer", "return=minimal");

    JsonDocument doc;
    doc["device_id"] = DEVICE_ID;
    doc["temperature"] = round(data.temperature * 10.0f) / 10.0f;
    doc["humidity"] = round(data.humidity * 10.0f) / 10.0f;
    doc["rain_rate"] = round(data.rain_rate * 100.0f) / 100.0f;
    doc["wind_speed"] = round(data.wind_speed * 10.0f) / 10.0f;

    String jsonBody;
    serializeJson(doc, jsonBody);

    int httpCode = http.POST(jsonBody);
    bool success = false;

    if (httpCode >= 200 && httpCode < 300) {
        Serial.printf("[Supabase] Data logged successfully! HTTP %d\n", httpCode);
        success = true;
    } else {
        Serial.printf("[Supabase] Failed to log data, HTTP %d: %s\n", httpCode, http.getString().c_str());
    }

    http.end();
    return success;
}

