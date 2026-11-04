import { AppConfig } from './configuration.interface';

export default (): AppConfig => ({
  port: parseInt(process.env.PORT, 10) || 8000,
  nodeEnv: process.env.NODE_ENV || 'development',
  apiPrefix: process.env.API_PREFIX || 'api',
  mqtt: {
    host: process.env.MQTT_BROKER_HOST || 'xxxxxxxx.ala.asia-southeast1.emqxsl.com',
    port: parseInt(process.env.MQTT_BROKER_PORT, 10) || 8883,
    username: process.env.MQTT_USERNAME || 'adht_device',
    password: process.env.MQTT_PASSWORD || '',
    useTls: (process.env.MQTT_USE_TLS || 'true') === 'true',
    clientId: process.env.MQTT_CLIENT_ID || 'adht_backend_gateway',
  },
  supabase: {
    url: process.env.SUPABASE_URL || '',
    key: process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_KEY || '',
    table: process.env.SUPABASE_TABLE || 'weather_logs',
  },
  firebase: {
    credentialsPath: process.env.FIREBASE_CREDENTIALS_PATH || 'serviceAccountKey.json',
    alertTopic: process.env.FIREBASE_ALERT_TOPIC || 'adht_weather_alerts',
  },
  openWeather: {
    apiKey: process.env.OPENWEATHER_API_KEY || '',
    defaultLat: parseFloat(process.env.DEFAULT_LAT) || 10.7769,
    defaultLon: parseFloat(process.env.DEFAULT_LON) || 106.7009,
  },
  thresholds: {
    tempMax: parseFloat(process.env.ALERT_TEMP_MAX) || 38.0,
    tempMin: parseFloat(process.env.ALERT_TEMP_MIN) || 10.0,
    humiMax: parseFloat(process.env.ALERT_HUMI_MAX) || 90.0,
    windMax: parseFloat(process.env.ALERT_WIND_MAX) || 15.0,
    rainMax: parseFloat(process.env.ALERT_RAIN_MAX) || 30.0,
  },
});
