import { BadRequestException, Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';

export interface WeatherRecord {
  device_id: string | null;
  temp: number;
  humi: number;
  rain_rate: number;
  wind_speed: number;
  recorded_at: string;
}

interface WeatherLogRow {
  created_at: string;
  device_id: string | null;
  temperature: number;
  humidity: number;
  rain_rate: number;
  wind_speed: number;
}

const WEATHER_COLUMNS = 'created_at,device_id,temperature,humidity,rain_rate,wind_speed';
const HISTORY_PAGE_SIZE = 500;
const HISTORY_RANGES = {
  '1h': { duration: 3600, bucket: 60 },
  '6h': { duration: 21600, bucket: 300 },
  '24h': { duration: 86400, bucket: 600 },
  '3d': { duration: 259200, bucket: 1800 },
  '7d': { duration: 604800, bucket: 3600 },
} as const;

@Injectable()
export class SupabaseService {
  private readonly logger = new Logger(SupabaseService.name);
  private readonly client: SupabaseClient;
  private readonly table: string;


  constructor(private readonly config: ConfigService) {
    const url = this.config.getOrThrow<string>('supabase.url');
    const key = this.config.getOrThrow<string>('supabase.key');

    if (!url || !key) {
      throw new Error('Missing Supabase configuration');
    }

    this.table = this.config.getOrThrow<string>('supabase.table');

    this.client = createClient(url, key, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
  }

  async saveTelemetry(data: Partial<WeatherRecord>): Promise<boolean> {
    const values = [data.temp, data.humi, data.rain_rate, data.wind_speed];
    if (!data.device_id?.trim() || values.some(value => typeof value !== 'number' || !Number.isFinite(value))) {
      this.logger.warn('Cannot save telemetry: missing device ID or invalid measurements');
      return false;
    }
    const recordedAt = data.recorded_at ? new Date(data.recorded_at) : new Date();
    if (!Number.isFinite(recordedAt.getTime())) return false;

    try {
      const { error } = await this.client.from(this.table).insert({
        device_id: data.device_id,
        temperature: data.temp,
        humidity: data.humi,
        rain_rate: data.rain_rate,
        wind_speed: data.wind_speed,
        created_at: recordedAt.toISOString(),
      });
      if (error) throw error;
      return true;
    } catch {
      this.logger.error('Failed to save telemetry to Supabase');
      return false;
    }
  }

  async getLatest(deviceId?: string): Promise<WeatherRecord | null> {
    try {
      let query = this.client.from(this.table).select(WEATHER_COLUMNS);
      if (deviceId !== undefined) query = query.eq('device_id', deviceId);
      const { data, error } = await query
        .order('created_at', { ascending: false })
        .order('id', { ascending: false })
        .limit(1)
        .maybeSingle<WeatherLogRow>();
      if (error) throw error;
      return data ? this.toWeatherRecord(data) : null;
    } catch {
      this.logger.error('Failed to fetch latest telemetry from Supabase');
      throw new ServiceUnavailableException('Unable to load latest weather data');
    }
  }

  async getHistory(deviceId: string, range: string = '24h'): Promise<WeatherRecord[]> {
    if (!deviceId?.trim()) throw new BadRequestException('device_id is required');
    if (!Object.prototype.hasOwnProperty.call(HISTORY_RANGES, range)) {
      throw new BadRequestException('range must be one of 1h, 6h, 24h, 3d, 7d');
    }
    const settings = HISTORY_RANGES[range as keyof typeof HISTORY_RANGES];
    const end = Date.now();
    const start = end - settings.duration * 1000;
    const buckets = new Map<number, { point: WeatherRecord; count: number }>();

    try {
      // Read every page: Supabase's response limit must not truncate the time range.
      for (let offset = 0; ; ) {
        const { data, error } = await this.client.from(this.table)
          .select(WEATHER_COLUMNS)
          .eq('device_id', deviceId)
          .gte('created_at', new Date(start).toISOString())
          .lte('created_at', new Date(end).toISOString())
          .order('created_at', { ascending: true })
          .order('id', { ascending: true })
          .range(offset, offset + HISTORY_PAGE_SIZE - 1)
          .returns<WeatherLogRow[]>();
        if (error) throw error;
        if (!data?.length) break;

        for (const row of data) {
          const time = Date.parse(row.created_at);
          const bucketTime = start + Math.floor((time - start) / (settings.bucket * 1000)) * settings.bucket * 1000;
          const existing = buckets.get(bucketTime);
          if (existing) {
            existing.point.temp += row.temperature;
            existing.point.humi += row.humidity;
            existing.point.rain_rate += row.rain_rate;
            existing.point.wind_speed += row.wind_speed;
            existing.count++;
          } else {
            buckets.set(bucketTime, {
              point: { ...this.toWeatherRecord(row), recorded_at: new Date(bucketTime).toISOString() },
              count: 1,
            });
          }
        }
        // Stop only on an empty page, even if the server caps pages below 500 rows.
        offset += data.length;
      }
    } catch {
      this.logger.error('Failed to fetch weather history from Supabase');
      throw new ServiceUnavailableException('Unable to load weather history');
    }

    return [...buckets.entries()].sort(([left], [right]) => left - right).map(([, { point, count }]) => ({
      ...point,
      temp: point.temp / count,
      humi: point.humi / count,
      rain_rate: point.rain_rate / count,
      wind_speed: point.wind_speed / count,
    }));
  }

  private toWeatherRecord(row: WeatherLogRow): WeatherRecord {
    return {
      device_id: row.device_id,
      temp: row.temperature,
      humi: row.humidity,
      rain_rate: row.rain_rate,
      wind_speed: row.wind_speed,
      recorded_at: row.created_at,
    };
  }
}
