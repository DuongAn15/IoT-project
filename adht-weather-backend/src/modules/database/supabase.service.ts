import { BadRequestException, ConflictException, Injectable, Logger, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, SupabaseClient } from '@supabase/supabase-js';
import type { Device } from '../devices/types/device.types';
import type { OperationRecord, StationConfigSnapshot } from '../devices/device-operations.service';
import type { DerivedMinuteLogRecord } from '../telemetry/minute-log-v2';

export interface WeatherRecord {
  device_id: string | null;
  temp: number;
  temp_min?: number;
  temp_max?: number;
  humi: number;
  rain_rate: number;
  rainfall_mm?: number;
  wind_speed: number;
  sample_count?: number;
  coverage?: number;
  /** Latest source record epoch ms in this bucket (increases when open bucket receives updates). */
  revision?: number;
  is_partial?: boolean;
  utc_offset_minutes?: number;
  source?: 'v2' | 'v2_cutover' | 'v1_legacy';
  rain_quality?: 'observed' | 'estimated';
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
  clock_quality?: 'synchronized' | 'unsynchronized';
  device_id: string;
  temperature: number;
  humidity: number;
  rain_rate: number;
  rainfall_mm: number;
  wind_speed: number;
  coverage_ms?: number;
  rain_coverage_ms?: number;
  dht_expected_count?: number;
  dht_valid_count?: number;
  wind_expected_count?: number;
  wind_valid_count?: number;
}

const WEATHER_COLUMNS = 'created_at,device_id,temperature,humidity,rain_rate,wind_speed';
const WEATHER_V2_COLUMNS =
  'recorded_at,clock_quality,device_id,temperature,humidity,rain_rate,rainfall_mm,wind_speed,coverage_ms,rain_coverage_ms,dht_expected_count,dht_valid_count,wind_expected_count,wind_valid_count';
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

  // Operation ledger. PostgreSQL functions own the transaction and row locks.
  async createP06Operation(args: {
    deviceId: string; kind: 'command' | 'config'; payload: Record<string, unknown>;
    requestId?: string; expectedVersion?: number; expiresAt: string; deploymentId?: string;
  }): Promise<{ operation: OperationRecord; duplicate: boolean }> {
    const { data, error } = await this.client.rpc('create_device_operation', {
      p_device: args.deviceId, p_kind: args.kind, p_payload: args.payload,
      p_request: args.requestId ?? null, p_expected: args.expectedVersion ?? null,
      p_expires: args.expiresAt, p_deployment: args.deploymentId ?? null,
    });
    if (error) {
      if (error.code === '23505' || error.code === '40001') throw new ConflictException(error.message);
      if (error.code === '22023') throw new BadRequestException(error.message);
      this.logger.error(`Operation creation failed: ${this.describeError(error)}`);
      throw new ServiceUnavailableException('Unable to create operation');
    }
    return data as { operation: OperationRecord; duplicate: boolean };
  }

  async getP06State(deviceId: string) {
    const { data, error } = await this.client.from('station_state').select('*')
      .eq('device_id', deviceId).maybeSingle();
    if (error) throw new ServiceUnavailableException('Unable to load station state');
    const recent = await this.client.from('device_operations').select('*')
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
    const { data, error } = await this.client.from('device_operations').select('*')
      .eq('device_id', deviceId).eq('operation_id', operationId).maybeSingle();
    if (error) throw new ServiceUnavailableException('Unable to load operation');
    if (!data) throw new NotFoundException(`Operation ${operationId} not found for ${deviceId}`);
    return data as OperationRecord;
  }

  async claimP06Operations(): Promise<OperationRecord[]> {
    const { data, error } = await this.client.rpc('claim_device_operations', { p_limit: 20 });
    if (error) throw new ServiceUnavailableException('Unable to claim operation outbox');
    return (data ?? []) as OperationRecord[];
  }

  async markP06Publish(deviceId: string, operationId: string, published: boolean): Promise<void> {
    const { error } = await this.client.rpc('publish_device_operation_result', {
      p_device: deviceId, p_operation: operationId, p_published: published,
    });
    if (error) throw new ServiceUnavailableException('Unable to record broker result');
  }

  async applyP06Ack(deviceId: string, ack: Record<string, unknown>): Promise<void> {
    const { error } = await this.client.rpc('apply_device_operation_ack', { p_device: deviceId, p_ack: ack });
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
        coverage_ms: record.coverage_ms,
        rain_coverage_ms: record.rain_coverage_ms,
        dht_expected_count: record.dht_expected_count,
        dht_valid_count: record.dht_valid_count,
        wind_expected_count: record.wind_expected_count,
        wind_valid_count: record.wind_valid_count,
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

  private resolveTimezoneOffsetMs(timezone: string, atMs: number): number {
    try {
      const formatter = new Intl.DateTimeFormat('en-US', {
        timeZone: timezone,
        timeZoneName: 'shortOffset',
      });
      const part = formatter.formatToParts(new Date(atMs)).find((p) => p.type === 'timeZoneName');
      const value = part?.value ?? 'GMT';
      if (value === 'GMT' || value === 'UTC') return 0;
      const match = /^GMT([+-])(\d{1,2})(?::?(\d{2}))?$/.exec(value);
      if (!match) return 0;
      const sign = match[1] === '-' ? -1 : 1;
      const hours = Number(match[2]);
      const minutes = Number(match[3] ?? '0');
      return sign * (hours * 60 + minutes) * 60 * 1000;
    } catch {
      throw new BadRequestException('timezone must be a valid IANA timezone');
    }
  }

  private computeBucketStartMs(timeMs: number, bucketSec: number, timezone: string): number {
    const bucketMs = bucketSec * 1000;
    const offsetMs = this.resolveTimezoneOffsetMs(timezone, timeMs);
    return Math.floor((timeMs + offsetMs) / bucketMs) * bucketMs - offsetMs;
  }

  async getHistory(
    deviceId: string,
    range: string = '24h',
    since?: string,
    timezone: string = 'Asia/Ho_Chi_Minh',
    from?: string,
    to?: string,
    dayStarts?: string[],
  ): Promise<WeatherRecord[]> {
    if (!deviceId?.trim()) throw new BadRequestException('device_id is required');
    if (!Object.prototype.hasOwnProperty.call(HISTORY_RANGES, range)) {
      throw new BadRequestException('range must be one of 1h, 6h, 24h, 3d, 7d');
    }
    const resolvedTimezone = timezone?.trim() || 'Asia/Ho_Chi_Minh';
    // Validate timezone up-front
    this.resolveTimezoneOffsetMs(resolvedTimezone, Date.now());

    const settings = HISTORY_RANGES[range as keyof typeof HISTORY_RANGES];
    const now = Date.now();
    const end = to ? Date.parse(to) : now;
    const start = from ? Date.parse(from) : end - settings.duration * 1000;
    if (!Number.isFinite(start) || !Number.isFinite(end) || start >= end || end > now + 60000 ||
        end - start > (range === '7d' ? 8 : 7) * 86400000 ||
        (!dayStarts && from && end - start > settings.duration * 1000)) {
      throw new BadRequestException('Invalid UTC history range');
    }
    const boundaries = dayStarts?.map((value) => Date.parse(value));
    if (boundaries && (range !== '7d' || boundaries.length !== 8 || boundaries.some((value) => !Number.isFinite(value)) ||
        boundaries[0] !== start || boundaries[7] < end ||
        boundaries.some((value, index) => index > 0 && value <= boundaries[index - 1]))) {
      throw new BadRequestException('day_starts must contain eight increasing UTC day boundaries');
    }
    const bucketFor = (time: number): number => {
      if (!boundaries) return this.computeBucketStartMs(time, settings.bucket, resolvedTimezone);
      for (let i = 6; i >= 0; i--) if (time >= boundaries[i]) return boundaries[i];
      return boundaries[0];
    };
    let effectiveStart = start;
    if (since !== undefined && since.trim() !== '') {
      const parsedSince = Date.parse(since);
      if (!Number.isFinite(parsedSince)) {
        throw new BadRequestException('since must be a valid ISO-8601 timestamp');
      }
      if (parsedSince > start) {
        effectiveStart = Math.min(parsedSince, end);
      }
    }

    const cutoverRaw = this.config?.get<string>('telemetry.v2CutoverAt') ?? process.env.V2_CUTOVER_AT;
    const cutoverMs = cutoverRaw ? Date.parse(cutoverRaw) : NaN;
    const hasCutover = Number.isFinite(cutoverMs);

    interface BucketAccum {
      deviceId: string | null;
      weightedTemp: number;
      weightedHumi: number;
      dhtWeightSum: number;
      weightedRainRate: number;
      rainWeightSum: number;
      weightedWindSpeed: number;
      windWeightSum: number;
      fallbackTempSum: number;
      fallbackHumiSum: number;
      fallbackRainRateSum: number;
      fallbackWindSum: number;
      count: number;
      effectiveCoverageMsSum: number;
      rainfallMmSum: number;
      tempMin: number;
      tempMax: number;
      latestRowMs: number;
    }

    const v1Buckets = new Map<number, BucketAccum>();
    const v2Buckets = new Map<number, BucketAccum>();

    const accumulate = (
      map: Map<number, BucketAccum>,
      bucketTime: number,
      rowMs: number,
      rowDeviceId: string | null,
      temp: number,
      humi: number,
      rainRate: number,
      windSpeed: number,
      rainfallMm: number,
      dhtWeight: number,
      windWeight: number,
      rainWeight: number,
      effectiveCoverageMs: number,
    ) => {
      const existing = map.get(bucketTime);
      if (existing) {
        existing.weightedTemp += temp * dhtWeight;
        existing.weightedHumi += humi * dhtWeight;
        existing.dhtWeightSum += dhtWeight;
        existing.weightedRainRate += rainRate * rainWeight;
        existing.rainWeightSum += rainWeight;
        existing.weightedWindSpeed += windSpeed * windWeight;
        existing.windWeightSum += windWeight;
        existing.fallbackTempSum += temp;
        existing.fallbackHumiSum += humi;
        existing.fallbackRainRateSum += rainRate;
        existing.fallbackWindSum += windSpeed;
        existing.count += 1;
        existing.effectiveCoverageMsSum += effectiveCoverageMs;
        existing.rainfallMmSum += rainfallMm;
        if (temp < existing.tempMin) existing.tempMin = temp;
        if (temp > existing.tempMax) existing.tempMax = temp;
        if (rowMs > existing.latestRowMs) existing.latestRowMs = rowMs;
      } else {
        map.set(bucketTime, {
          deviceId: rowDeviceId,
          weightedTemp: temp * dhtWeight,
          weightedHumi: humi * dhtWeight,
          dhtWeightSum: dhtWeight,
          weightedRainRate: rainRate * rainWeight,
          rainWeightSum: rainWeight,
          weightedWindSpeed: windSpeed * windWeight,
          windWeightSum: windWeight,
          fallbackTempSum: temp,
          fallbackHumiSum: humi,
          fallbackRainRateSum: rainRate,
          fallbackWindSum: windSpeed,
          count: 1,
          effectiveCoverageMsSum: effectiveCoverageMs,
          rainfallMmSum: rainfallMm,
          tempMin: temp,
          tempMax: temp,
          latestRowMs: rowMs,
        });
      }
    };

    try {
      // Read every page from legacy v1 table
      for (let offset = 0; ; ) {
        const { data, error } = await this.client.from(this.table)
          .select(WEATHER_COLUMNS)
          .eq('device_id', deviceId)
          .gte('created_at', new Date(effectiveStart).toISOString())
          .lte('created_at', new Date(end).toISOString())
          .order('created_at', { ascending: true })
          .order('id', { ascending: true })
          .range(offset, offset + HISTORY_PAGE_SIZE - 1)
          .returns<WeatherLogRow[]>();
        if (error) throw error;
        if (!data?.length) break;

        for (const row of data) {
          const time = Date.parse(row.created_at);
          if (time < start || time >= end) continue;
          if (hasCutover && time >= cutoverMs) continue;
          const bucketTime = bucketFor(time);
          accumulate(
            v1Buckets,
            bucketTime,
            time,
            row.device_id,
            row.temperature,
            row.humidity,
            row.rain_rate,
            row.wind_speed,
            0,
            1,
            1,
            1,
            5000,
          );
        }
        // Stop only on an empty page, even if the server caps pages below 500 rows.
        offset += data.length;
      }

      // Union with v2 minute-log table when configured
      if (this.v2Table) {
        const sinceIso = new Date(effectiveStart).toISOString();
        const endIso = new Date(end).toISOString();
        for (let offset = 0; ; ) {
          let v2Query = this.client.from(this.v2Table)
            .select(WEATHER_V2_COLUMNS)
            .eq('device_id', deviceId)
            .lte('recorded_at', endIso) as unknown as {
              gte: (col: string, val: string) => unknown;
              or?: (expr: string) => unknown;
              order: (col: string, opts: { ascending: boolean }) => unknown;
              range: (from: number, to: number) => {
                returns: <T>() => Promise<{ data: T | null; error: unknown }>;
              };
            };
          if (effectiveStart > start && typeof v2Query.or === 'function') {
            v2Query = v2Query.or(`recorded_at.gte.${sinceIso},received_at.gte.${sinceIso}`) as typeof v2Query;
          } else {
            v2Query = v2Query.gte('recorded_at', sinceIso) as typeof v2Query;
          }
          v2Query = (v2Query.order('recorded_at', { ascending: true }) as typeof v2Query)
            .order('id', { ascending: true }) as typeof v2Query;
          const { data, error } = await v2Query
            .range(offset, offset + HISTORY_PAGE_SIZE - 1)
            .returns<WeatherLogV2Row[]>();
          if (error) throw error;
          if (!data?.length) break;

          for (const row of data) {
            const time = Date.parse(row.recorded_at);
            // Synchronized minute logs represent [interval_start, interval_end).
            // Assign a log ending exactly on a bucket boundary to the preceding bucket.
            // Unsynchronized logs use received_at, which is an instant, not an interval end.
            const sampleTime = row.clock_quality === 'unsynchronized' ? time : time - 1;
            if (sampleTime < start || sampleTime >= end) continue;
            if (hasCutover && time < cutoverMs) continue;
            const bucketTime = bucketFor(sampleTime);
            const covMs = row.coverage_ms ?? 60000;
            const rainCovMs = row.rain_coverage_ms ?? covMs;
            const dhtWeight = row.dht_valid_count ?? covMs;
            const windWeight = row.wind_valid_count ?? covMs;
            const dhtRatio =
              row.dht_expected_count && row.dht_expected_count > 0 && row.dht_valid_count !== undefined
                ? Math.min(1, row.dht_valid_count / row.dht_expected_count)
                : 1;
            const effectiveCovMs = covMs * dhtRatio;

            accumulate(
              v2Buckets,
              bucketTime,
              time,
              row.device_id,
              row.temperature,
              row.humidity,
              row.rain_rate,
              row.wind_speed,
              row.rainfall_mm,
              dhtWeight,
              windWeight,
              rainCovMs,
              effectiveCovMs,
            );
          }
          offset += data.length;
        }
      }
    } catch (error: unknown) {
      this.logger.error(`Failed to fetch weather history from Supabase: ${this.describeError(error)}`);
      throw new ServiceUnavailableException('Unable to load weather history');
    }

    const bucketMs = settings.bucket * 1000;
    const allTimes = new Set<number>([...v1Buckets.keys(), ...v2Buckets.keys()]);
    return [...allTimes].sort((left, right) => left - right).map((bucketTime) => {
      const utcOffsetMinutes = Math.round(this.resolveTimezoneOffsetMs(resolvedTimezone, bucketTime) / 60000);
      const bucketDurationMs = boundaries
        ? Math.min(end, boundaries[boundaries.indexOf(bucketTime) + 1]) - bucketTime
        : bucketMs;
      const v2 = v2Buckets.get(bucketTime);
      if (v2) {
        const cutoverDay = Boolean(boundaries && hasCutover && v1Buckets.has(bucketTime) &&
          bucketTime < cutoverMs && cutoverMs < boundaries[boundaries.indexOf(bucketTime) + 1]);
        const coverage = Math.min(1, Number((v2.effectiveCoverageMsSum / bucketDurationMs).toFixed(3)));
        return {
          device_id: v2.deviceId,
          temp: v2.dhtWeightSum > 0 ? v2.weightedTemp / v2.dhtWeightSum : v2.fallbackTempSum / v2.count,
          temp_min: v2.tempMin,
          temp_max: v2.tempMax,
          humi: v2.dhtWeightSum > 0 ? v2.weightedHumi / v2.dhtWeightSum : v2.fallbackHumiSum / v2.count,
          rain_rate: v2.rainWeightSum > 0 ? v2.weightedRainRate / v2.rainWeightSum : v2.fallbackRainRateSum / v2.count,
          rainfall_mm: Number(v2.rainfallMmSum.toFixed(3)),
          wind_speed: v2.windWeightSum > 0 ? v2.weightedWindSpeed / v2.windWeightSum : v2.fallbackWindSum / v2.count,
          sample_count: v2.count,
          coverage,
          revision: v2.latestRowMs,
          is_partial: cutoverDay || (boundaries ? end < boundaries[boundaries.indexOf(bucketTime) + 1] : end < bucketTime + bucketMs) || coverage < 1,
          utc_offset_minutes: utcOffsetMinutes,
          source: cutoverDay ? 'v2_cutover' : 'v2',
          rain_quality: 'observed',
          recorded_at: new Date(bucketTime).toISOString(),
        };
      }
      const v1 = v1Buckets.get(bucketTime)!;
      const avgRainRate =
        v1.rainWeightSum > 0 ? v1.weightedRainRate / v1.rainWeightSum : v1.fallbackRainRateSum / v1.count;
      const coverage = Math.min(1, Number((v1.effectiveCoverageMsSum / bucketDurationMs).toFixed(3)));
      return {
        device_id: v1.deviceId,
        temp: v1.dhtWeightSum > 0 ? v1.weightedTemp / v1.dhtWeightSum : v1.fallbackTempSum / v1.count,
        temp_min: v1.tempMin,
        temp_max: v1.tempMax,
        humi: v1.dhtWeightSum > 0 ? v1.weightedHumi / v1.dhtWeightSum : v1.fallbackHumiSum / v1.count,
        rain_rate: avgRainRate,
        rainfall_mm: Number(((avgRainRate * bucketDurationMs) / 3600000).toFixed(3)),
        wind_speed: v1.windWeightSum > 0 ? v1.weightedWindSpeed / v1.windWeightSum : v1.fallbackWindSum / v1.count,
        sample_count: v1.count,
        coverage,
        revision: v1.latestRowMs,
        is_partial: (boundaries ? end < boundaries[boundaries.indexOf(bucketTime) + 1] : end < bucketTime + bucketMs) || coverage < 1,
        utc_offset_minutes: utcOffsetMinutes,
        source: 'v1_legacy',
        rain_quality: 'estimated',
        recorded_at: new Date(bucketTime).toISOString(),
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
