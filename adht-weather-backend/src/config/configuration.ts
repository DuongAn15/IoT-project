import { AppConfig } from './configuration.interface';

function parseCorsOrigins(raw?: string): string[] {
  if (!raw) return [];
  return raw
    .split(',')
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0 && origin !== '*');
}

function parseDeviceDeployments(raw?: string): Record<string, string> {
  const map: Record<string, string> = {};
  if (!raw) return map;
  for (const entry of raw.split(',')) {
    const trimmed = entry.trim();
    const eq = trimmed.indexOf('=');
    if (eq > 0) {
      const devId = trimmed.slice(0, eq).trim();
      const depId = trimmed.slice(eq + 1).trim();
      if (devId && depId) map[devId] = depId;
    }
  }
  return map;
}

export default (): AppConfig => ({
  port: parseInt(process.env.PORT, 10) || 8000,
  nodeEnv: process.env.NODE_ENV || 'development',
  apiPrefix: process.env.API_PREFIX || 'api',
  corsOrigins: parseCorsOrigins(process.env.CORS_ORIGINS),
  auth: {
    apiToken: process.env.API_AUTH_TOKEN?.trim() || undefined,
    webhookSecret: process.env.WEBHOOK_SECRET?.trim() || undefined,
    enableWebhookTelemetry: (process.env.ENABLE_WEBHOOK_TELEMETRY || 'false') === 'true',
    allowedDevices: parseCorsOrigins(process.env.ALLOWED_DEVICE_IDS),
    deviceDeployments: parseDeviceDeployments(process.env.DEVICE_DEPLOYMENTS),
    v2DedupFile: process.env.V2_DEDUP_FILE?.trim() || undefined,
    v2CutoverEnabled: (process.env.V2_CUTOVER_ENABLED || 'false') === 'true',
  },
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
    // Server-side only: require service role key (never fall back to anon key).
    key: process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_KEY || '',
    table: process.env.SUPABASE_TABLE || 'weather_logs',
    v2Table: process.env.SUPABASE_V2_TABLE?.trim() || 'weather_logs_v2',
  },
  firebase: {
    credentialsPath: process.env.FIREBASE_CREDENTIALS_PATH || 'serviceAccountKey.json',
    // Nội dung service account (JSON thô hoặc base64) cho môi trường cloud không mount được file.
    credentialsJson: process.env.FIREBASE_CREDENTIALS_JSON || undefined,
    alertTopic: process.env.FIREBASE_ALERT_TOPIC || 'adht_weather_alerts',
  },
  /* Deferred forecast configuration; restore when forecast is reactivated.
  openWeather: {
    apiKey: process.env.OPENWEATHER_API_KEY || '',
    defaultLat: parseFloat(process.env.DEFAULT_LAT || '10.7769'),
    defaultLon: parseFloat(process.env.DEFAULT_LON || '106.7009'),
  },
  */
  thresholds: {
    tempMax: parseFloat(process.env.ALERT_TEMP_MAX) || 38.0,
    tempMin: parseFloat(process.env.ALERT_TEMP_MIN) || 10.0,
    humiMax: parseFloat(process.env.ALERT_HUMI_MAX) || 90.0,
    windMax: parseFloat(process.env.ALERT_WIND_MAX) || 15.0,
    rainMax: parseFloat(process.env.ALERT_RAIN_MAX) || 30.0,
  },
});
