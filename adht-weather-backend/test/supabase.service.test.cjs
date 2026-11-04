const assert = require('node:assert/strict');
const { test } = require('node:test');
const { SupabaseService } = require('../dist/modules/database/supabase.service');

function setup(responses) {
  const calls = [];
  const query = {};
  for (const method of ['select', 'eq', 'gte', 'lte', 'order', 'limit', 'range']) {
    query[method] = (...args) => { calls.push([method, ...args]); return query; };
  }
  for (const method of ['insert', 'maybeSingle', 'returns']) {
    query[method] = async (...args) => {
      calls.push([method, ...args]);
      if (!responses.length) throw new Error('Unexpected query');
      const response = responses.shift();
      if (response instanceof Error) throw response;
      return response;
    };
  }
  const service = Object.create(SupabaseService.prototype);
  service.client = { from: table => { calls.push(['from', table]); return query; } };
  service.table = 'weather_logs';
  service.logger = { warn() {}, error() {} };
  return { service, calls };
}

const measurement = { device_id: 'station1', temp: 30, humi: 60, rain_rate: 2, wind_speed: 5 };
const row = {
  device_id: 'station1', temperature: 30, humidity: 60, rain_rate: 2,
  wind_speed: 5, created_at: '2026-11-04T00:30:00.000Z',
};

test('save maps only existing columns and accepts optional recorded_at', async () => {
  const { service, calls } = setup([{ error: null }]);
  assert.equal(await service.saveTelemetry({ ...measurement, rain_daily: 15, recorded_at: row.created_at }), true);
  assert.deepEqual(calls.find(call => call[0] === 'insert')[1], {
    device_id: 'station1', temperature: 30, humidity: 60, rain_rate: 2,
    wind_speed: 5, created_at: row.created_at,
  });
});

test('save rejects invalid input and reports database or transport failures', async () => {
  const { service, calls } = setup([{ error: { code: '42501' } }, new Error('network')]);
  assert.equal(await service.saveTelemetry({ ...measurement, temp: NaN }), false);
  assert.equal(await service.saveTelemetry({ ...measurement, device_id: '' }), false);
  assert.equal(await service.saveTelemetry({ ...measurement, recorded_at: 'invalid' }), false);
  assert.equal(calls.length, 0);
  assert.equal(await service.saveTelemetry(measurement), false);
  assert.equal(await service.saveTelemetry(measurement), false);
});

test('latest filters by device, maps fields, and orders deterministically', async () => {
  const { service, calls } = setup([{ data: row, error: null }]);
  assert.deepEqual(await service.getLatest('station1'), { ...measurement, recorded_at: row.created_at });
  assert.ok(calls.some(call => call[0] === 'eq' && call[1] === 'device_id' && call[2] === 'station1'));
  assert.deepEqual(calls.filter(call => call[0] === 'order'), [
    ['order', 'created_at', { ascending: false }], ['order', 'id', { ascending: false }],
  ]);
});

test('latest returns null only for empty data; query failures become 503', async () => {
  const { service, calls } = setup([{ data: null, error: null }, { error: { code: '42501' } }]);
  assert.equal(await service.getLatest(), null);
  assert.equal(calls.some(call => call[0] === 'eq'), false);
  await assert.rejects(service.getLatest(), error => error.getStatus() === 503);
});

test('history reads all capped pages and averages each time bucket in chronological order', async () => {
  const originalNow = Date.now;
  Date.now = () => Date.parse('2026-11-04T01:00:00.000Z');
  try {
    const { service, calls } = setup([
      { data: [row], error: null },
      { data: [{ ...row, temperature: 34, created_at: '2026-11-04T00:30:30.000Z' }], error: null },
      { data: [{ ...row, created_at: '2026-11-04T00:31:10.000Z' }], error: null },
      { data: [], error: null },
    ]);
    const result = await service.getHistory('station1', '1h');
    assert.equal(result.length, 2);
    assert.equal(result[0].temp, 32);
    assert.equal(result[0].rain_rate, 2);
    assert.equal(result[0].recorded_at, '2026-11-04T00:30:00.000Z');
    assert.equal(result[1].recorded_at, '2026-11-04T00:31:00.000Z');
    assert.deepEqual(calls.filter(call => call[0] === 'range'), [
      ['range', 0, 499], ['range', 1, 500], ['range', 2, 501], ['range', 3, 502],
    ]);
    assert.ok(calls.some(call => call[0] === 'lte' && call[2] === '2026-11-04T01:00:00.000Z'));
  } finally {
    Date.now = originalNow;
  }
});

test('history handles empty data, validates range/device, and fails without partial results', async () => {
  const { service } = setup([{ data: [], error: null }, { error: { code: '42501' } }]);
  assert.deepEqual(await service.getHistory('station1'), []);
  await assert.rejects(service.getHistory('station1', 'invalid'), error => error.getStatus() === 400);
  await assert.rejects(service.getHistory(''), error => error.getStatus() === 400);
  await assert.rejects(service.getHistory('station1'), error => error.getStatus() === 503);
});
