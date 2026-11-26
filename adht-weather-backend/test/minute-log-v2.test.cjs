const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const { validateAndDeriveMinuteLogV2 } = require('../dist/modules/telemetry/minute-log-v2');
const { MqttService } = require('../dist/modules/mqtt/mqtt.service');

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
