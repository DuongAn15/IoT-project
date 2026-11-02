export interface AppConfig {
  port: number;
  nodeEnv: string;
  apiPrefix: string;
  mqtt: {
    host: string;
    port: number;
    username: string;
    password?: string;
    useTls: boolean;
    clientId: string;
  };
  supabase: {
    url: string;
    key: string;
    table: string;
  };
  firebase: {
    credentialsPath: string;
    alertTopic: string;
  };
  openWeather: {
    apiKey?: string;
    defaultLat: number;
    defaultLon: number;
  };
  thresholds: {
    tempMax: number;
    tempMin: number;
    humiMax: number;
    windMax: number;
    rainMax: number;
  };
}

