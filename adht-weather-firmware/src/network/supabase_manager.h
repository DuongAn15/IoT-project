#ifndef SUPABASE_MANAGER_H
#define SUPABASE_MANAGER_H

#include "../config.h"
#include "../types.h"
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>

class SupabaseManager {
public:
    SupabaseManager();
    void begin();
    bool logWeatherData(const WeatherData &data);

private:
    WiFiClientSecure secureClient;
    String endpointUrl;
};

extern SupabaseManager supabaseMgr;

#endif // SUPABASE_MANAGER_H

