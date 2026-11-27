import { createHash } from 'crypto';

export type V2ErrorCode =
  | 'invalid_schema'
  | 'identity_mismatch'
  | 'invalid_counter_range'
  | 'unknown_calibration'
  | 'conflict'
  | 'storage_unavailable';

export interface V2ValidationError {
  code: V2ErrorCode;
  message: string;
  retryable: boolean;
}

export interface MinuteLogMetricSummary {
  unit: string;
  sum: number;
  count: number;
  min?: number;
  max?: number;
  latest?: number;
}

export interface MinuteLogV2Payload {
  schema_version: 2;
  type: 'minute_log';
  device_id: string;
  deployment_id: string;
  boot_id: string;
  window_sequence: number;
  clock_quality: 'synchronized' | 'unsynchronized';
  interval_start?: string;
  interval_end?: string;
  uptime_start_ms?: number;
  uptime_end_ms?: number;
  metrics: {
    temperature?: MinuteLogMetricSummary;
    humidity?: MinuteLogMetricSummary;
    wind_speed?: MinuteLogMetricSummary;
  };
  rain: {
    counter_epoch: string;
    calibration_version: string;
    tip_count_start: number;
    tip_count_end: number;
  };
  quality: {
    dht_expected_count: number;
    dht_valid_count: number;
    wind_expected_count: number;
    wind_valid_count: number;
    coverage_ms: number;
    rain_coverage_ms: number;
  };
}

export interface DerivedMinuteLogRecord {
  identityKey: string;
  payloadHash: string;
  device_id: string;
  deployment_id: string;
  boot_id: string;
  window_sequence: number;
  clock_quality: 'synchronized' | 'unsynchronized';
  temp: number;
  humi: number;
  wind_speed: number;
  rain_rate: number;
  rainfall_mm: number;
  coverage_ms: number;
  rain_coverage_ms: number;
  dht_expected_count: number;
  dht_valid_count: number;
  wind_expected_count: number;
  wind_valid_count: number;
  recorded_at: string;
}

export const MAX_V2_PAYLOAD_BYTES = 8192;

// Immutable calibration catalog: mm per tipping-bucket pulse by calibration_version.
export const RAIN_CALIBRATION_MM_PER_TIP: Readonly<Record<string, number>> = {
  'rain-bucket-v1': (1000000.0 / 9498.0) * 6.0 / 1000.0,
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function isNonNegativeInt(value: unknown): value is number {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0;
}

function canonicalStringify(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalStringify).join(',')}]`;
  }
  if (isRecord(value)) {
    const keys = Object.keys(value).sort();
    return `{${keys.map((k) => `${JSON.stringify(k)}:${canonicalStringify(value[k])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

export function hashV2Payload(payload: unknown): string {
  return createHash('sha256').update(canonicalStringify(payload)).digest('hex');
}

function validateMetric(
  raw: unknown,
  minBound: number,
  maxBound: number,
  fieldName: string,
): { ok: true; value?: MinuteLogMetricSummary } | { ok: false; error: V2ValidationError } {
  if (raw === undefined) return { ok: true, value: undefined };
  if (!isRecord(raw)) {
    return {
      ok: false,
      error: { code: 'invalid_schema', message: `${fieldName} must be an object`, retryable: false },
    };
  }
  if (!isNonNegativeInt(raw.count) || !isFiniteNumber(raw.sum) || !isNonEmptyString(raw.unit)) {
    return {
      ok: false,
      error: { code: 'invalid_schema', message: `${fieldName} missing unit/sum/count`, retryable: false },
    };
  }
  if (raw.count > 0) {
    const avg = raw.sum / raw.count;
    if (!Number.isFinite(avg) || avg < minBound || avg > maxBound) {
      return {
        ok: false,
        error: { code: 'invalid_schema', message: `${fieldName} average out of bounds`, retryable: false },
      };
    }
  }
  return {
    ok: true,
    value: {
      unit: raw.unit,
      sum: raw.sum,
      count: raw.count,
      min: isFiniteNumber(raw.min) ? raw.min : undefined,
      max: isFiniteNumber(raw.max) ? raw.max : undefined,
      latest: isFiniteNumber(raw.latest) ? raw.latest : undefined,
    },
  };
}

export function validateAndDeriveMinuteLogV2(
  raw: unknown,
  topicDeviceId: string,
  receivedAt: Date = new Date(),
  expectedDeploymentId?: string,
): { ok: true; record: DerivedMinuteLogRecord } | { ok: false; error: V2ValidationError } {
  if (!isRecord(raw)) {
    return { ok: false, error: { code: 'invalid_schema', message: 'Expected JSON object', retryable: false } };
  }
  if (raw.schema_version !== 2 || raw.type !== 'minute_log') {
    return {
      ok: false,
      error: { code: 'invalid_schema', message: 'Invalid schema_version or type', retryable: false },
    };
  }
  if (!isNonEmptyString(raw.device_id) || !isNonEmptyString(raw.deployment_id) || !isNonEmptyString(raw.boot_id)) {
    return {
      ok: false,
      error: { code: 'invalid_schema', message: 'Missing device_id, deployment_id, or boot_id', retryable: false },
    };
  }
  if (raw.device_id !== topicDeviceId) {
    return {
      ok: false,
      error: { code: 'identity_mismatch', message: 'device_id does not match MQTT topic', retryable: false },
    };
  }
  if (expectedDeploymentId && raw.deployment_id !== expectedDeploymentId) {
    return {
      ok: false,
      error: {
        code: 'identity_mismatch',
        message: 'deployment_id does not match registered device deployment',
        retryable: false,
      },
    };
  }
  if (typeof raw.window_sequence !== 'number' || !Number.isInteger(raw.window_sequence) || raw.window_sequence < 1) {
    return {
      ok: false,
      error: { code: 'invalid_schema', message: 'window_sequence must be an integer >= 1', retryable: false },
    };
  }

  let intervalSeconds = 60;
  let recordedAtIso = receivedAt.toISOString();
  if (raw.clock_quality === 'synchronized') {
    if (!isNonEmptyString(raw.interval_start) || !isNonEmptyString(raw.interval_end)) {
      return {
        ok: false,
        error: { code: 'invalid_schema', message: 'Synchronized log requires interval_start and interval_end', retryable: false },
      };
    }
    const startMs = Date.parse(raw.interval_start);
    const endMs = Date.parse(raw.interval_end);
    if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs) {
      return {
        ok: false,
        error: { code: 'invalid_schema', message: 'Invalid interval_start/interval_end range', retryable: false },
      };
    }
    intervalSeconds = (endMs - startMs) / 1000;
    recordedAtIso = new Date(endMs).toISOString();
  } else if (raw.clock_quality === 'unsynchronized') {
    if (!isFiniteNumber(raw.uptime_start_ms) || !isFiniteNumber(raw.uptime_end_ms) ||
        raw.uptime_start_ms < 0 || raw.uptime_end_ms <= raw.uptime_start_ms) {
      return {
        ok: false,
        error: { code: 'invalid_schema', message: 'Invalid uptime_start_ms/uptime_end_ms range', retryable: false },
      };
    }
    intervalSeconds = (raw.uptime_end_ms - raw.uptime_start_ms) / 1000;
  } else {
    return {
      ok: false,
      error: { code: 'invalid_schema', message: 'clock_quality must be synchronized or unsynchronized', retryable: false },
    };
  }

  if (!isRecord(raw.rain) || !isNonEmptyString(raw.rain.counter_epoch) || !isNonEmptyString(raw.rain.calibration_version)) {
    return {
      ok: false,
      error: { code: 'invalid_schema', message: 'Missing rain counter_epoch or calibration_version', retryable: false },
    };
  }
  const mmPerTip = RAIN_CALIBRATION_MM_PER_TIP[raw.rain.calibration_version];
  if (mmPerTip === undefined) {
    return {
      ok: false,
      error: { code: 'unknown_calibration', message: 'Unknown rain calibration_version', retryable: false },
    };
  }
  if (!isNonNegativeInt(raw.rain.tip_count_start) || !isNonNegativeInt(raw.rain.tip_count_end)) {
    return {
      ok: false,
      error: { code: 'invalid_counter_range', message: 'Rain tip counts must be non-negative integers', retryable: false },
    };
  }
  if (raw.rain.tip_count_end < raw.rain.tip_count_start) {
    return {
      ok: false,
      error: { code: 'invalid_counter_range', message: 'tip_count_end cannot be less than tip_count_start', retryable: false },
    };
  }

  if (!isRecord(raw.quality) ||
      !isNonNegativeInt(raw.quality.dht_expected_count) ||
      !isNonNegativeInt(raw.quality.dht_valid_count) ||
      !isNonNegativeInt(raw.quality.wind_expected_count) ||
      !isNonNegativeInt(raw.quality.wind_valid_count) ||
      !isNonNegativeInt(raw.quality.coverage_ms) ||
      !isNonNegativeInt(raw.quality.rain_coverage_ms)) {
    return {
      ok: false,
      error: { code: 'invalid_schema', message: 'Invalid quality block', retryable: false },
    };
  }

  if (!isRecord(raw.metrics)) {
    return { ok: false, error: { code: 'invalid_schema', message: 'Missing metrics block', retryable: false } };
  }
  const tempRes = validateMetric(raw.metrics.temperature, -40, 80, 'metrics.temperature');
  if ('error' in tempRes) return { ok: false, error: tempRes.error };
  const humiRes = validateMetric(raw.metrics.humidity, 0, 100, 'metrics.humidity');
  if ('error' in humiRes) return { ok: false, error: humiRes.error };
  const windRes = validateMetric(raw.metrics.wind_speed, 0, 100, 'metrics.wind_speed');
  if ('error' in windRes) return { ok: false, error: windRes.error };

  const tempAvg = tempRes.value && tempRes.value.count > 0 ? tempRes.value.sum / tempRes.value.count : 0;
  const humiAvg = humiRes.value && humiRes.value.count > 0 ? humiRes.value.sum / humiRes.value.count : 0;
  const windAvg = windRes.value && windRes.value.count > 0 ? windRes.value.sum / windRes.value.count : 0;

  const deltaTips = raw.rain.tip_count_end - raw.rain.tip_count_start;
  const rainfallMm = Number((deltaTips * mmPerTip).toFixed(4));
  const rainRateAvg = intervalSeconds > 0 ? Number(((rainfallMm * 3600) / intervalSeconds).toFixed(2)) : 0;

  return {
    ok: true,
    record: {
      identityKey: `${raw.device_id}:${raw.deployment_id}:${raw.boot_id}:${raw.window_sequence}`,
      payloadHash: hashV2Payload(raw),
      device_id: raw.device_id,
      deployment_id: raw.deployment_id,
      boot_id: raw.boot_id,
      window_sequence: raw.window_sequence,
      clock_quality: raw.clock_quality,
      temp: Number(tempAvg.toFixed(2)),
      humi: Number(humiAvg.toFixed(2)),
      wind_speed: Number(windAvg.toFixed(2)),
      rain_rate: rainRateAvg,
      rainfall_mm: rainfallMm,
      coverage_ms: raw.quality.coverage_ms,
      rain_coverage_ms: raw.quality.rain_coverage_ms,
      dht_expected_count: raw.quality.dht_expected_count,
      dht_valid_count: raw.quality.dht_valid_count,
      wind_expected_count: raw.quality.wind_expected_count,
      wind_valid_count: raw.quality.wind_valid_count,
      recorded_at: recordedAtIso,
    },
  };
}
