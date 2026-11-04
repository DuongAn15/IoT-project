import type { ForecastDay, ForecastPeriod } from '../types/forecast.types';

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function number(value: unknown): number {
  if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('Invalid forecast number');
  return value;
}

function localDate(timestamp: number, timezone: number): string {
  return new Date(timestamp + timezone * 1000).toISOString().slice(0, 10);
}

export function buildForecast(data: unknown, now: number): { timezone: number; days: ForecastDay[] } {
  if (!isObject(data) || String(data.cod) !== '200' || !isObject(data.city) || !Array.isArray(data.list)) {
    throw new Error('Invalid OpenWeather forecast response');
  }
  const timezone = number(data.city.timezone);
  if (Math.abs(timezone) > 86400) throw new Error('Invalid forecast timezone');
  const today = localDate(now, timezone);
  const lastDay = localDate(now + 3 * 86400000, timezone);
  const grouped = new Map<string, ForecastPeriod[]>();

  for (const item of data.list) {
    if (!isObject(item) || !isObject(item.main) || !isObject(item.wind) ||
      !Array.isArray(item.weather) || !isObject(item.weather[0])) {
      throw new Error('Invalid forecast period');
    }
    const time = number(item.dt) * 1000;
    const date = localDate(time, timezone);
    if (date <= today || date > lastDay) continue;
    const condition = item.weather[0];
    if (typeof condition.description !== 'string' || typeof condition.icon !== 'string') {
      throw new Error('Invalid forecast condition');
    }
    const period: ForecastPeriod = {
      timestamp: new Date(time).toISOString(),
      temp: number(item.main.temp),
      temp_min: number(item.main.temp_min),
      temp_max: number(item.main.temp_max),
      humidity: number(item.main.humidity),
      wind_speed: number(item.wind.speed),
      rain_mm: item.rain === undefined ? 0 : number(isObject(item.rain) ? item.rain['3h'] : undefined),
      precipitation_probability: number(item.pop),
      description: condition.description,
      icon: condition.icon,
    };
    if (period.rain_mm < 0 || period.precipitation_probability < 0 || period.precipitation_probability > 1) {
      throw new Error('Invalid precipitation forecast');
    }
    const periods = grouped.get(date) || [];
    periods.push(period);
    grouped.set(date, periods);
  }

  const days = [...grouped.entries()].sort(([left], [right]) => left.localeCompare(right)).map(([date, periods]) => ({
    date,
    temp_min: Math.min(...periods.map(period => period.temp_min)),
    temp_max: Math.max(...periods.map(period => period.temp_max)),
    humidity: periods.reduce((sum, period) => sum + period.humidity, 0) / periods.length,
    wind_speed: periods.reduce((sum, period) => sum + period.wind_speed, 0) / periods.length,
    rain_mm: periods.reduce((sum, period) => sum + period.rain_mm, 0),
    precipitation_probability: Math.max(...periods.map(period => period.precipitation_probability)),
    periods: periods.sort((left, right) => left.timestamp.localeCompare(right.timestamp)),
  }));
  if (days.length !== 3) throw new Error('Incomplete three-day forecast');
  return { timezone, days };
}
