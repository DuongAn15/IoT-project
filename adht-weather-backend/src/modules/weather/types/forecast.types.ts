export interface ForecastPeriod {
  timestamp: string;
  temp: number;
  temp_min: number;
  temp_max: number;
  humidity: number;
  wind_speed: number;
  rain_mm: number;
  precipitation_probability: number;
  description: string;
  icon: string;
}

export interface ForecastDay {
  date: string;
  temp_min: number;
  temp_max: number;
  humidity: number;
  wind_speed: number;
  rain_mm: number;
  precipitation_probability: number;
  periods: ForecastPeriod[];
}

export interface WeatherForecast {
  status: 'success';
  coords: { lat: number; lon: number };
  timezone_offset_seconds: number;
  forecast_days: ForecastDay[];
}
