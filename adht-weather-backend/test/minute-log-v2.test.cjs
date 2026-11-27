const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const { validateAndDeriveMinuteLogV2 } = require('../dist/modules/telemetry/minute-log-v2');
const { MqttService } = require('../dist/modules/mqtt/mqtt.service');
const { SupabaseService } = require('../dist/modules/database/supabase.service');

const fixturesDir = path.resolve(__dirname, '../../docs/contracts/v2');
const readFixture = (name) => JSON.parse(fs.readFileSync(path.join(fixturesDir, name), 'utf8'));

test('validates v2/minute-log-valid.json fixture and derives averages & rainfall_mm', () => {
  const valid = readFixture('minute-log-valid.json');
  const res = validateAndDeriveMinuteLogV2(valid, valid.device_id);
  assert.equal(res.ok, true);
  assert.equal(res.record.device_id, 'dev-001');
  assert.equal(res.record.temp, 30.0);
  assert.equal(res.record.humi, 68.0);
  assert.equal(res.record.wind_speed, 2.0);
  assert.equal(res.record.rainfall_mm, 0);
  assert.equal(res.record.recorded_at, '2026-11-26T03:21:00.000Z');
});

test('rejects v2/minute-log-invalid-missing-sequence.json with invalid_schema', () => {
  const invalid = readFixture('minute-log-invalid-missing-sequence.json');
  const res = validateAndDeriveMinuteLogV2(invalid, invalid.device_id);
  assert.equal(res.ok, false);
  assert.equal(res.error.code, 'invalid_schema');
  assert.equal(res.error.retryable, false);
});

test('rejects v2/minute-log-invalid-counter-decrease.json with invalid_counter_range', () => {
  const invalid = readFixture('minute-log-invalid-counter-decrease.json');
  const res = validateAndDeriveMinuteLogV2(invalid, invalid.device_id);
  assert.equal(res.ok, false);
  assert.equal(res.error.code, 'invalid_counter_range');
  assert.equal(res.error.retryable, false);
});

test('rejects topic/device_id mismatch and unknown calibration_version', () => {
  const valid = readFixture('minute-log-valid.json');
  const mismatch = validateAndDeriveMinuteLogV2(valid, 'other-dev');
  assert.equal(mismatch.ok, false);
  assert.equal(mismatch.error.code, 'identity_mismatch');

  const badCal = structuredClone(valid);
  badCal.rain.calibration_version = 'unknown-v99';
  const calRes = validateAndDeriveMinuteLogV2(badCal, badCal.device_id);
  assert.equal(calRes.ok, false);
  assert.equal(calRes.error.code, 'unknown_calibration');
});

test('MqttService v2 receiver is idempotent on duplicates, flags conflicts, and retries after DB failure', async () => {
  let savedCalls = 0;
  let alertCalls = 0;
  let saveShouldFail = true;

  const service = new MqttService(
    {},
    { saveTelemetry: async () => { savedCalls++; return !saveShouldFail; } },
    { broadcastTelemetry: () => {}, broadcastStatus: () => {} },
    { checkAndAlert: async () => { alertCalls++; } },
  );

  const valid = readFixture('minute-log-valid.json');

  // 1. Transient DB failure -> storage_unavailable, retryable=true, not cached as persisted
  const failed = await service.processMinuteLogV2(valid.device_id, valid);
  assert.equal(failed.status, 'rejected');
  assert.equal(failed.errorCode, 'storage_unavailable');
  assert.equal(failed.retryable, true);
  assert.equal(alertCalls, 0);

  // 2. Retry succeeds
  saveShouldFail = false;
  const ok = await service.processMinuteLogV2(valid.device_id, valid);
  assert.equal(ok.status, 'persisted');
  assert.equal(alertCalls, 1);

  // 3. Exact duplicate -> idempotent, no extra DB/alert
  const dup = await service.processMinuteLogV2(valid.device_id, valid);
  assert.equal(dup.status, 'duplicate');
  assert.equal(savedCalls, 2);
  assert.equal(alertCalls, 1);

  // 4. Same identity, mutated payload -> conflict
  const conflictPayload = structuredClone(valid);
  conflictPayload.metrics.temperature.sum = 999.0;
  const conflict = await service.processMinuteLogV2(valid.device_id, conflictPayload);
  assert.equal(conflict.status, 'rejected');
  assert.equal(conflict.errorCode, 'conflict');
  assert.equal(conflict.retryable, false);
  assert.equal(savedCalls, 2);
});

test('MqttService handleMessage routes v2 topic, rejects oversized payloads, and bounds queue', async () => {
  let savedCalls = 0;
  const service = new MqttService(
    { get: (key) => (key === 'auth.deviceDeployments' ? { 'dev-001': 'dep-002' } : undefined) },
    { saveTelemetry: async () => { savedCalls++; return true; } },
    { broadcastTelemetry: () => {}, broadcastStatus: () => {} },
    { checkAndAlert: async () => {} },
  );

  const valid = readFixture('minute-log-valid.json');
  await service.handleMessage(
    'adht/weather/dev-001/telemetry/log',
    Buffer.from(JSON.stringify(valid)),
  );
  assert.equal(savedCalls, 1);

  // Deployment mismatch rejected
  const wrongDep = structuredClone(valid);
  wrongDep.deployment_id = 'dep-wrong';
  wrongDep.window_sequence = 999;
  const depRes = await service.processMinuteLogV2('dev-001', wrongDep);
  assert.equal(depRes.status, 'rejected');
  assert.equal(depRes.errorCode, 'identity_mismatch');

  // Oversized payload (> 8192 bytes) ignored cleanly
  const oversized = Buffer.from(JSON.stringify({ ...valid, padding: 'x'.repeat(9000) }));
  await service.handleMessage('adht/weather/dev-001/telemetry/log', oversized);
  assert.equal(savedCalls, 1);

  // Bounded queue drops when full
  service.drainQueue = () => {}; // pause draining to test queue cap
  let accepted = 0;
  for (let i = 0; i < 205; i++) {
    if (service.enqueueMessage('adht/weather/dev-001/telemetry/log', Buffer.from('{}'))) {
      accepted++;
    }
  }
  assert.equal(accepted, 200);
});

test('MqttService persists v2 dedup/conflict across service restart via V2_DEDUP_FILE', async () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'adht-v2-dedup-'));
  const dedupFile = path.join(tmpDir, 'v2-dedup.jsonl');
  try {
    let savedCalls = 0;
    const config = { get: (key) => (key === 'auth.v2DedupFile' ? dedupFile : undefined) };
    const deps = [
      { saveTelemetry: async () => { savedCalls++; return true; } },
      { broadcastTelemetry: () => {}, broadcastStatus: () => {} },
      { checkAndAlert: async () => {} },
    ];

    const instance1 = new MqttService(config, ...deps);
    const valid = readFixture('minute-log-valid.json');
    assert.equal((await instance1.processMinuteLogV2(valid.device_id, valid)).status, 'persisted');
    assert.equal(savedCalls, 1);

    // Simulate backend restart with a fresh MqttService reading the same journal
    const instance2 = new MqttService(config, ...deps);
    assert.equal((await instance2.processMinuteLogV2(valid.device_id, valid)).status, 'duplicate');
    assert.equal(savedCalls, 1);

    const conflictPayload = structuredClone(valid);
    conflictPayload.metrics.temperature.sum = 888.0;
    const conflict = await instance2.processMinuteLogV2(valid.device_id, conflictPayload);
    assert.equal(conflict.status, 'rejected');
    assert.equal(conflict.errorCode, 'conflict');
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test('SupabaseService.saveMinuteLogV2 handles persisted, DB 23505 duplicate, and conflict', async () => {
  const valid = readFixture('minute-log-valid.json');
  const { record } = validateAndDeriveMinuteLogV2(valid, valid.device_id);

  let insertResp = { error: null };
  let lookupResp = { data: null, error: null };
  const svc = Object.create(SupabaseService.prototype);
  svc.v2Table = 'weather_logs_v2';
  svc.logger = { warn() {}, error() {} };
  svc.describeError = () => '23505';
  svc.client = {
    from: () => ({
      insert: async () => insertResp,
      select: () => ({
        eq: () => ({ eq: () => ({ eq: () => ({ eq: () => ({ maybeSingle: async () => lookupResp }) }) }) }),
      }),
    }),
  };

  assert.equal(await svc.saveMinuteLogV2(record), 'persisted');

  insertResp = { error: { code: '23505' } };
  lookupResp = { data: { payload_hash: record.payloadHash }, error: null };
  assert.equal(await svc.saveMinuteLogV2(record), 'duplicate');

  lookupResp = { data: { payload_hash: 'different-hash' }, error: null };
  assert.equal(await svc.saveMinuteLogV2(record), 'conflict');
});

test('MqttService skips v1 DB write when V2_CUTOVER_ENABLED=true while keeping WS broadcast', async () => {
  let v1Saves = 0;
  let wsBroadcasts = 0;
  const service = new MqttService(
    { get: (key) => (key === 'auth.v2CutoverEnabled' ? true : undefined) },
    { saveTelemetry: async () => { v1Saves++; return true; } },
    { broadcastTelemetry: () => { wsBroadcasts++; }, broadcastStatus: () => {} },
    { checkAndAlert: async () => {} },
  );

  await service.handleMessage(
    'adht/weather/adht_weather_01/telemetry',
    Buffer.from(JSON.stringify({
      device_id: 'adht_weather_01',
      temp: 25,
      humi: 70,
      rain_rate: 0,
      rain_total: 0,
      wind_speed: 2,
    })),
  );
  assert.equal(v1Saves, 0);
  assert.equal(wsBroadcasts, 1);
});

test('SupabaseService.getHistory aligns 24h buckets to clock boundaries across midnight', async () => {
  const originalNow = Date.now;
  Date.now = () => Date.parse('2026-11-26T17:09:48.179Z'); // 00:09:48 GMT+7
  try {
    const svc = Object.create(SupabaseService.prototype);
    svc.table = 'weather_logs';
    svc.v2Table = 'weather_logs_v2';
    svc.logger = { warn() {}, error() {} };
    const responses = [
      { data: [], error: null },
      {
        data: [
          {
            device_id: 'adht_weather_01',
            temperature: 24.44,
            humidity: 68,
            rain_rate: 0,
            rainfall_mm: 0,
            wind_speed: 0,
            recorded_at: '2026-11-26T17:08:50.000Z', // 00:08:50 GMT+7
          },
        ],
        error: null,
      },
      { data: [], error: null },
    ];
    const query = {};
    for (const m of ['select', 'eq', 'gte', 'lte', 'order', 'range']) {
      query[m] = () => query;
    }
    query.returns = async () => responses.shift();
    svc.client = { from: () => query };

    const history = await svc.getHistory('adht_weather_01', '24h');
    assert.equal(history.length, 1);
    assert.equal(history[0].recorded_at, '2026-11-26T17:00:00.000Z'); // 00:00:00 GMT+7 (today!)
  } finally {
    Date.now = originalNow;
  }
});

test('MqttService rejects v2 minute_log in production when DEVICE_DEPLOYMENTS binding is missing', async () => {
  const service = new MqttService(
    {
      get: (key) => {
        if (key === 'nodeEnv') return 'production';
        if (key === 'auth.deviceDeployments') return {};
        return undefined;
      },
    },
    { saveMinuteLogV2: async () => 'persisted' },
    { broadcastTelemetry: () => {}, broadcastStatus: () => {} },
    { checkAndAlert: async () => {} },
  );

  const valid = readFixture('minute-log-valid.json');
  const res = await service.processMinuteLogV2(valid.device_id, valid);
  assert.equal(res.status, 'rejected');
  assert.equal(res.errorCode, 'identity_mismatch');
  assert.equal(res.retryable, false);
});

test('SupabaseService.getHistory exposes temp_min, temp_max, provenance, and respects since', async () => {
  const originalNow = Date.now;
  Date.now = () => Date.parse('2026-11-27T01:00:00.000Z');
  try {
    const svc = Object.create(SupabaseService.prototype);
    svc.table = 'weather_logs';
    svc.v2Table = 'weather_logs_v2';
    svc.logger = { warn() {}, error() {} };
    const gteCalls = [];
    const responses = [
      { data: [], error: null },
      {
        data: [
          {
            device_id: 'adht_weather_01',
            temperature: 22.0,
            humidity: 70,
            rain_rate: 0,
            rainfall_mm: 0.5,
            wind_speed: 1.5,
            recorded_at: '2026-11-27T00:10:00.000Z',
          },
          {
            device_id: 'adht_weather_01',
            temperature: 26.0,
            humidity: 66,
            rain_rate: 6,
            rainfall_mm: 1.0,
            wind_speed: 2.5,
            recorded_at: '2026-11-27T00:15:00.000Z',
          },
        ],
        error: null,
      },
      { data: [], error: null },
    ];
    const query = {};
    for (const m of ['select', 'eq', 'lte', 'order', 'range']) {
      query[m] = () => query;
    }
    query.gte = (col, val) => { gteCalls.push([col, val]); return query; };
    query.returns = async () => responses.shift();
    svc.client = { from: () => query };

    const sinceIso = '2026-11-27T00:05:00.000Z';
    const history = await svc.getHistory('adht_weather_01', '24h', sinceIso);
    assert.equal(history.length, 1);
    assert.equal(history[0].temp, 24.0);
    assert.equal(history[0].temp_min, 22.0);
    assert.equal(history[0].temp_max, 26.0);
    assert.equal(history[0].rainfall_mm, 1.5);
    assert.equal(history[0].sample_count, 2);
    assert.equal(history[0].source, 'v2');
    assert.equal(history[0].rain_quality, 'observed');
    assert.equal(history[0].coverage, 0.2);
    assert.equal(history[0].is_partial, true);
    assert.equal(history[0].revision, Date.parse('2026-11-27T00:15:00.000Z'));
    assert.ok(gteCalls.some(([, val]) => val === sinceIso));
  } finally {
    Date.now = originalNow;
  }
});

test('SupabaseService.getHistory aligns buckets to station timezone, updates revision on inclusive since, and respects V2_CUTOVER_AT', async () => {
  const originalNow = Date.now;
  const originalCutover = process.env.V2_CUTOVER_AT;
  Date.now = () => Date.parse('2026-11-27T02:00:00.000Z');
  process.env.V2_CUTOVER_AT = '2026-11-27T01:00:00.000Z';

  try {
    const svc = Object.create(SupabaseService.prototype);
    svc.table = 'weather_logs';
    svc.v2Table = 'weather_logs_v2';
    svc.logger = { error() {}, warn() {}, log() {} };
    const v1Rows = [
      {
        device_id: 'adht_weather_01',
        temperature: 20,
        humidity: 70,
        rain_rate: 0,
        wind_speed: 1,
        created_at: '2026-11-27T00:35:00.000Z', // before cutover
      },
      {
        device_id: 'adht_weather_01',
        temperature: 99,
        humidity: 99,
        rain_rate: 99,
        wind_speed: 99,
        created_at: '2026-11-27T01:35:00.000Z', // after cutover -> ignored
      },
    ];
    const v2Rows = [
      {
        device_id: 'adht_weather_01',
        temperature: 25,
        humidity: 60,
        rain_rate: 0,
        rainfall_mm: 0.4,
        wind_speed: 2,
        recorded_at: '2026-11-27T01:35:00.000Z', // after cutover
      },
    ];

    const makeMockClient = () => {
      const doneTables = new Set();
      return {
        from: (table) => {
          const rows = table === 'weather_logs_v2' ? v2Rows : v1Rows;
          const query = {};
          for (const m of ['select', 'eq', 'gte', 'lte', 'order', 'range']) {
            query[m] = () => query;
          }
          query.returns = async () => {
            if (doneTables.has(table)) return { data: [], error: null };
            doneTables.add(table);
            return { data: rows, error: null };
          };
          return query;
        },
      };
    };

    svc.client = makeMockClient();

    // Asia/Kolkata (+05:30) 1h bucket (3600s):
    // 00:35 UTC = 06:05 IST -> 06:00 IST (00:30 UTC)
    // 01:35 UTC = 07:05 IST -> 07:00 IST (01:30 UTC)
    const kolkataHistory = await svc.getHistory('adht_weather_01', '7d', undefined, 'Asia/Kolkata');
    assert.equal(kolkataHistory.length, 2);
    assert.equal(kolkataHistory[0].recorded_at, '2026-11-27T00:30:00.000Z');
    assert.equal(kolkataHistory[0].source, 'v1_legacy');
    assert.equal(kolkataHistory[1].recorded_at, '2026-11-27T01:30:00.000Z');
    assert.equal(kolkataHistory[1].source, 'v2');

    // In Asia/Ho_Chi_Minh (+07:00) 7d bucket (3600s): 00:35 UTC (07:35 ICT) -> 00:00 UTC, 01:35 UTC (08:35 ICT) -> 01:00 UTC
    svc.client = makeMockClient();
    const ictHistory = await svc.getHistory('adht_weather_01', '7d', undefined, 'Asia/Ho_Chi_Minh');
    assert.equal(ictHistory.length, 2);
    assert.equal(ictHistory[0].recorded_at, '2026-11-27T00:00:00.000Z');
    assert.equal(ictHistory[0].source, 'v1_legacy');
    assert.equal(ictHistory[1].recorded_at, '2026-11-27T01:00:00.000Z');
    assert.equal(ictHistory[1].source, 'v2');
    assert.equal(ictHistory[1].temp, 25);

    const firstRev = ictHistory[1].revision;

    // Simulate open bucket receiving another minute log and re-syncing with inclusive since at bucket boundary
    v2Rows.push({
      device_id: 'adht_weather_01',
      temperature: 27,
      humidity: 62,
      rain_rate: 1.2,
      rainfall_mm: 0.6,
      wind_speed: 2.5,
      recorded_at: '2026-11-27T01:40:00.000Z',
    });
    svc.client = makeMockClient();
    const resync = await svc.getHistory(
      'adht_weather_01',
      '7d',
      '2026-11-27T01:00:00.000Z',
      'Asia/Ho_Chi_Minh',
    );
    const updatedBucket = resync.find((b) => b.recorded_at === '2026-11-27T01:00:00.000Z');
    assert.ok(updatedBucket);
    assert.equal(updatedBucket.sample_count, 2);
    assert.equal(updatedBucket.rainfall_mm, 1.0);
    assert.ok(updatedBucket.revision > firstRev);

    await assert.rejects(
      () => svc.getHistory('adht_weather_01', '24h', undefined, 'Invalid/Timezone'),
      /valid IANA timezone/,
    );
  } finally {
    Date.now = originalNow;
    if (originalCutover === undefined) {
      delete process.env.V2_CUTOVER_AT;
    } else {
      process.env.V2_CUTOVER_AT = originalCutover;
    }
  }
});

test('SupabaseService.getHistory weights averages by valid sample counts and computes true coverage from quality fields', async () => {
  const originalNow = Date.now;
  Date.now = () => Date.parse('2026-11-27T01:00:00.000Z');
  try {
    const svc = Object.create(SupabaseService.prototype);
    svc.table = 'weather_logs';
    svc.v2Table = 'weather_logs_v2';
    svc.logger = { error() {}, warn() {}, log() {} };

    const responses = [
      { data: [], error: null },
      {
        data: [
          {
            device_id: 'adht_weather_01',
            temperature: 20.0,
            humidity: 60.0,
            rain_rate: 0.0,
            rainfall_mm: 0.0,
            wind_speed: 1.0,
            coverage_ms: 30000,
            rain_coverage_ms: 30000,
            dht_expected_count: 10,
            dht_valid_count: 1,
            wind_expected_count: 10,
            wind_valid_count: 1,
            recorded_at: '2026-11-27T00:01:00.000Z',
          },
          {
            device_id: 'adht_weather_01',
            temperature: 30.0,
            humidity: 80.0,
            rain_rate: 6.0,
            rainfall_mm: 0.1,
            wind_speed: 4.0,
            coverage_ms: 60000,
            rain_coverage_ms: 60000,
            dht_expected_count: 10,
            dht_valid_count: 9,
            wind_expected_count: 10,
            wind_valid_count: 9,
            recorded_at: '2026-11-27T00:02:00.000Z',
          },
        ],
        error: null,
      },
      { data: [], error: null },
    ];
    const query = {};
    for (const m of ['select', 'eq', 'gte', 'lte', 'order', 'range']) {
      query[m] = () => query;
    }
    query.returns = async () => responses.shift();
    svc.client = { from: () => query };

    // 24h bucket = 600s = 600_000ms
    const history = await svc.getHistory('adht_weather_01', '24h');
    assert.equal(history.length, 1);
    // Weighted temp: (20*1 + 30*9) / 10 = 29.0 (simple mean would be 25.0)
    assert.equal(history[0].temp, 29.0);
    // Weighted wind: (1*1 + 4*9) / 10 = 3.7
    assert.equal(history[0].wind_speed, 3.7);
    // Effective coverage: (30000*(1/10) + 60000*(9/10)) / 600000 = 57000 / 600000 = 0.095
    assert.equal(history[0].coverage, 0.095);
    assert.equal(history[0].is_partial, true);
  } finally {
    Date.now = originalNow;
  }
});
