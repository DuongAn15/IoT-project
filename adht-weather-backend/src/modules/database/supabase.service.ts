import { BadRequestException, ConflictException, Injectable, Logger, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import type { Device } from '../devices/types/device.types';
import type { OperationRecord, StationConfigSnapshot } from '../devices/device-operations.service';
import type { DerivedMinuteLogRecord } from '../telemetry/minute-log-v2';

export interface WeatherRecord {
  device_id: string | null;
  temp: number;
  humi: number;
  rain_rate: number;
  rainfall_mm?: number;
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

interface WeatherLogV2Row {
  recorded_at: string;
  device_id: string;
  temperature: number;
  humidity: number;
  rain_rate: number;
  rainfall_mm: number;
  wind_speed: number;
}

const WEATHER_COLUMNS = 'created_at,device_id,temperature,humidity,rain_rate,wind_speed';
const WEATHER_V2_COLUMNS = 'recorded_at,device_id,temperature,humidity,rain_rate,rainfall_mm,wind_speed';
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
  private readonly v2Table?: string;


  constructor(private readonly config: ConfigService) {
    const url = this.config.getOrThrow<string>('supabase.url');
    const key = this.config.getOrThrow<string>('supabase.key');

    if (!url || !key) {
      throw new Error('Missing Supabase configuration');
    }

    this.table = this.config.getOrThrow<string>('supabase.table');
    this.v2Table = this.config.get<string>('supabase.v2Table') || 'weather_logs_v2';

    this.client = createClient(url, key, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
    });
  }

  // P06 operation ledger. PostgreSQL functions own the transaction and row locks.
  async createP06Operation(args: {
    deviceId: string; kind: 'command' | 'config'; payload: Record<string, unknown>;
    requestId?: string; expectedVersion?: number; expiresAt: string; deploymentId?: string;
  }): Promise<{ operation: OperationRecord; duplicate: boolean }> {
    const { data, error } = await this.client.rpc('p06_create_operation', {
      p_device: args.deviceId, p_kind: args.kind, p_payload: args.payload,
      p_request: args.requestId ?? null, p_expected: args.expectedVersion ?? null,
      p_expires: args.expiresAt, p_deployment: args.deploymentId ?? null,
    });
    if (error) {
      if (error.code === '23505' || error.code === '40001') throw new ConflictException(error.message);
      if (error.code === '22023') throw new BadRequestException(error.message);
      this.logger.error(`P06 operation creation failed: ${this.describeError(error)}`);
      throw new ServiceUnavailableException('Unable to create operation');
    }
    return data as { operation: OperationRecord; duplicate: boolean };
  }

  async getP06State(deviceId: string) {
    const { data, error } = await this.client.from('p06_station_state').select('*')
      .eq('device_id', deviceId).maybeSingle();
    if (error) throw new ServiceUnavailableException('Unable to load station state');
    const recent = await this.client.from('p06_operations').select('*')
      .eq('device_id', deviceId).order('created_at', { ascending: false }).limit(20);
    if (recent.error) throw new ServiceUnavailableException('Unable to load station operations');
    const defaults: StationConfigSnapshot = {
      temp_max: 38, temp_min: 10, humi_max: 90, wind_max: 15, rain_max: 30,
      auto_warning: true, buzzer: true,
    };
    return data ? { ...data, recent_operations: recent.data ?? [] } : {
      device_id: deviceId, desired_version: 0, desired_config: defaults,
      reported_version: 0, reported_config: null, recent_operations: recent.data ?? [],
    };
  }

  async getP06Operation(deviceId: string, operationId: string): Promise<OperationRecord> {
    const { data, error } = await this.client.from('p06_operations').select('*')
      .eq('device_id', deviceId).eq('operation_id', operationId).maybeSingle();
    if (error) throw new ServiceUnavailableException('Unable to load operation');
    if (!data) throw new NotFoundException(`Operation ${operationId} not found for ${deviceId}`);
    return data as OperationRecord;
  }

  async claimP06Operations(): Promise<OperationRecord[]> {
    const { data, error } = await this.client.rpc('p06_claim_operations', { p_limit: 20 });
    if (error) throw new ServiceUnavailableException('Unable to claim operation outbox');
    return (data ?? []) as OperationRecord[];
  }

  async markP06Publish(deviceId: string, operationId: string, published: boolean): Promise<void> {
    const { error } = await this.client.rpc('p06_publish_result', {
      p_device: deviceId, p_operation: operationId, p_published: published,
    });
    if (error) throw new ServiceUnavailableException('Unable to record broker result');
  }

  async applyP06Ack(deviceId: string, ack: Record<string, unknown>): Promise<void> {
    const { error } = await this.client.rpc('p06_apply_ack', { p_device: deviceId, p_ack: ack });
    if (error) throw new ServiceUnavailableException('Unable to record device ACK');
  }

  async createDevice(device: Device): Promise<Device> {
    const { data, error } = await this.client.from('devices')
      .insert(device)
      .select('device_id,name,mac')
      .single<Device>();
    if (error) {
      if (error.code === '23505') {
        throw new ConflictException('Device ID or MAC already exists');
      }
      this.logger.error(`Failed to create device: ${this.describeError(error)}`);
      throw new ServiceUnavailableException('Unable to create device');
    }
    return data;
  }

  async getDevices(): Promise<Device[]> {
    const devices: Device[] = [];
    const pageSize = 500;
    for (let offset = 0; ; ) {
      const { data, error } = await this.client.from('devices')
        .select('device_id,name,mac')
        .order('device_id', { ascending: true })
        .range(offset, offset + pageSize - 1)
        .returns<Device[]>();
      if (error) {
        this.logger.error(`Failed to fetch devices: ${this.describeError(error)}`);
        throw new ServiceUnavailableException('Unable to load devices');
      }
      if (!data?.length) return devices;
      devices.push(...data);
      offset += data.length;
    }
  }

  async getDevice(deviceId: string): Promise<Device> {
    const { data, error } = await this.client.from('devices')
      .select('device_id,name,mac')
      .eq('device_id', deviceId)
      .maybeSingle<Device>();
    if (error) {
      this.logger.error(`Failed to fetch device: ${this.describeError(error)}`);
      throw new ServiceUnavailableException('Unable to load device');
    }
    if (!data) throw new NotFoundException('Device not found');
    return data;
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
    } catch (error: unknown) {
      this.logger.error(`Failed to save telemetry to Supabase: ${this.describeError(error)}`);
      return false;
    }
  }

  async saveMinuteLogV2(
    record: DerivedMinuteLogRecord,
  ): Promise<'persisted' | 'duplicate' | 'conflict' | 'error'> {
    const targetTable = this.v2Table || 'weather_logs_v2';
    try {
      const { error } = await this.client.from(targetTable).insert({
        device_id: record.device_id,
        deployment_id: record.deployment_id,
        boot_id: record.boot_id,
        window_sequence: record.window_sequence,
        payload_hash: record.payloadHash,
        clock_quality: record.clock_quality,
        recorded_at: record.recorded_at,
        temperature: record.temp,
        humidity: record.humi,
        wind_speed: record.wind_speed,
        rain_rate: record.rain_rate,
        rainfall_mm: record.rainfall_mm,
      });

      if (!error) return 'persisted';

      if (error.code === '23505') {
        const { data: existing, error: lookupError } = await this.client
          .from(targetTable)
          .select('payload_hash')
          .eq('device_id', record.device_id)
          .eq('deployment_id', record.deployment_id)
          .eq('boot_id', record.boot_id)
          .eq('window_sequence', record.window_sequence)
          .maybeSingle<{ payload_hash: string }>();
        if (lookupError || !existing) return 'error';
        return existing.payload_hash === record.payloadHash ? 'duplicate' : 'conflict';
      }

      throw error;
    } catch (error: unknown) {
      this.logger.error(`Failed to save v2 minute_log to Supabase: ${this.describeError(error)}`);
      return 'error';
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
      const v1Record = data ? this.toWeatherRecord(data) : null;

      if (!this.v2Table) {
        return v1Record;
      }

      let v2Query = this.client.from(this.v2Table).select(WEATHER_V2_COLUMNS);
      if (deviceId !== undefined) v2Query = v2Query.eq('device_id', deviceId);
      const { data: v2Data, error: v2Error } = await v2Query
        .order('recorded_at', { ascending: false })
        .order('id', { ascending: false })
        .limit(1)
        .maybeSingle<WeatherLogV2Row>();
      if (v2Error) throw v2Error;
      if (!v2Data) return v1Record;

      const v2Record: WeatherRecord = {
        device_id: v2Data.device_id,
        temp: v2Data.temperature,
        humi: v2Data.humidity,
        rain_rate: v2Data.rain_rate,
        rainfall_mm: v2Data.rainfall_mm,
        wind_speed: v2Data.wind_speed,
        recorded_at: v2Data.recorded_at,
      };
      if (!v1Record) return v2Record;
      return Date.parse(v2Record.recorded_at) >= Date.parse(v1Record.recorded_at)
        ? v2Record
        : v1Record;
    } catch (error: unknown) {
      this.logger.error(`Failed to fetch latest telemetry from Supabase: ${this.describeError(error)}`);
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
    const v1Buckets = new Map<number, { point: WeatherRecord; count: number }>();
    const v2Buckets = new Map<number, { point: WeatherRecord; count: number; rainfallMmSum: number }>();

    try {
      // Read every page from legacy v1 table
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
          const bucketMs = settings.bucket * 1000;
          const bucketTime = Math.floor(time / bucketMs) * bucketMs;
          const existing = v1Buckets.get(bucketTime);
          if (existing) {
            existing.point.temp += row.temperature;
            existing.point.humi += row.humidity;
            existing.point.rain_rate += row.rain_rate;
            existing.point.wind_speed += row.wind_speed;
            existing.count++;
          } else {
            v1Buckets.set(bucketTime, {
              point: { ...this.toWeatherRecord(row), recorded_at: new Date(bucketTime).toISOString() },
              count: 1,
            });
          }
        }
        // Stop only on an empty page, even if the server caps pages below 500 rows.
        offset += data.length;
      }

      // Union with v2 minute-log table when configured
      if (this.v2Table) {
        for (let offset = 0; ; ) {
          const { data, error } = await this.client.from(this.v2Table)
            .select(WEATHER_V2_COLUMNS)
            .eq('device_id', deviceId)
            .gte('recorded_at', new Date(start).toISOString())
            .lte('recorded_at', new Date(end).toISOString())
            .order('recorded_at', { ascending: true })
            .order('id', { ascending: true })
            .range(offset, offset + HISTORY_PAGE_SIZE - 1)
            .returns<WeatherLogV2Row[]>();
          if (error) throw error;
          if (!data?.length) break;

          for (const row of data) {
            const time = Date.parse(row.recorded_at);
            const bucketMs = settings.bucket * 1000;
            const bucketTime = Math.floor(time / bucketMs) * bucketMs;
            const existing = v2Buckets.get(bucketTime);
            if (existing) {
              existing.point.temp += row.temperature;
              existing.point.humi += row.humidity;
              existing.point.rain_rate += row.rain_rate;
              existing.point.wind_speed += row.wind_speed;
              existing.rainfallMmSum += row.rainfall_mm;
              existing.count++;
            } else {
              v2Buckets.set(bucketTime, {
                point: {
                  device_id: row.device_id,
                  temp: row.temperature,
                  humi: row.humidity,
                  rain_rate: row.rain_rate,
                  wind_speed: row.wind_speed,
                  recorded_at: new Date(bucketTime).toISOString(),
                },
                count: 1,
                rainfallMmSum: row.rainfall_mm,
              });
            }
          }
          offset += data.length;
        }
      }
    } catch (error: unknown) {
      this.logger.error(`Failed to fetch weather history from Supabase: ${this.describeError(error)}`);
      throw new ServiceUnavailableException('Unable to load weather history');
    }

    const allTimes = new Set<number>([...v1Buckets.keys(), ...v2Buckets.keys()]);
    return [...allTimes].sort((left, right) => left - right).map((bucketTime) => {
      const v2 = v2Buckets.get(bucketTime);
      if (v2) {
        return {
          ...v2.point,
          temp: v2.point.temp / v2.count,
          humi: v2.point.humi / v2.count,
          rain_rate: v2.point.rain_rate / v2.count,
          rainfall_mm: Number(v2.rainfallMmSum.toFixed(3)),
          wind_speed: v2.point.wind_speed / v2.count,
        };
      }
      const { point, count } = v1Buckets.get(bucketTime)!;
      const avgRainRate = point.rain_rate / count;
      return {
        ...point,
        temp: point.temp / count,
        humi: point.humi / count,
        rain_rate: avgRainRate,
        rainfall_mm: Number(((avgRainRate * settings.bucket) / 3600).toFixed(3)),
        wind_speed: point.wind_speed / count,
      };
    });
  }

  private describeError(error: unknown): string {
    // Raw errors/details can contain row contents or request credentials.
    if (typeof error !== 'object' || error === null || !('code' in error)) {
      return 'No database error code; check network, endpoint and API key';
    }
    const code = error.code;
    if (typeof code !== 'string' || !/^[A-Z0-9]{5,12}$/.test(code)) {
      return 'No database error code; check network, endpoint and API key';
    }
    const hints: Record<string, string> = {
      '42501': 'Permission denied; check role grants and RLS policies',
      '23502': 'Required database column is missing a value',
      '23503': 'Foreign key constraint failed',
      '23505': 'Unique constraint failed',
      '23514': 'Check constraint failed',
      '42P01': 'Database table does not exist',
      '42703': 'Database column does not exist; check schema mapping',
      PGRST205: 'Table not found in the API schema cache',
      PGRST204: 'Column not found in the API schema cache',
      PGRST301: 'JWT could not be verified',
      PGRST303: 'JWT claims validation failed',
    };
    return `${code}: ${hints[code] || 'Check Supabase database/API logs'}`;
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
