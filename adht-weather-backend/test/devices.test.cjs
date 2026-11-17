const assert = require('node:assert/strict');
const { test } = require('node:test');
const { ValidationPipe } = require('@nestjs/common');
const { SupabaseService } = require('../dist/modules/database/supabase.service');
const { DevicesService } = require('../dist/modules/devices/devices.service');
const { DevicesController } = require('../dist/modules/devices/devices.controller');
const { CreateDeviceDto } = require('../dist/modules/devices/dto/create-device.dto');

const device = { device_id: 'adht_weather_02', name: 'Trạm 02', mac: '02:00:00:00:00:02' };

function setup(results) {
  const calls = [];
  const query = {};
  for (const method of ['insert', 'select', 'eq', 'order', 'range']) {
    query[method] = (...args) => { calls.push([method, ...args]); return query; };
  }
  for (const method of ['single', 'maybeSingle', 'returns']) {
    query[method] = async () => results.shift();
  }
  const db = Object.create(SupabaseService.prototype);
  db.client = { from: table => { assert.equal(table, 'devices'); return query; } };
  db.logger = { error() {} };
  const controller = new DevicesController(new DevicesService({}, db));
  return { controller, calls };
}

test('creates a device through controller, service and database', async () => {
  const { controller, calls } = setup([{ data: device, error: null }]);
  assert.deepEqual(await controller.createDevice(device), device);
  assert.deepEqual(calls[0], ['insert', device]);
});

test('returns 409 for duplicate ID or MAC and 503 for database errors', async () => {
  for (const [code, status] of [['23505', 409], ['42501', 503]]) {
    const { controller } = setup([{ data: null, error: { code } }]);
    await assert.rejects(controller.createDevice(device), error => error.getStatus() === status);
  }
});

test('lists all devices across multiple database pages', async () => {
  const page = Array.from({ length: 500 }, (_, i) => ({ ...device, device_id: `device_${i}` }));
  const { controller, calls } = setup([
    { data: page, error: null },
    { data: [device], error: null },
  ]);
  assert.equal((await controller.getDevices()).length, 501);
  assert.deepEqual(calls.filter(call => call[0] === 'range'), [
    ['range', 0, 499], ['range', 500, 999],
  ]);
});

test('returns an empty list when no devices exist', async () => {
  const { controller } = setup([{ data: [], error: null }]);
  assert.deepEqual(await controller.getDevices(), []);
});

test('gets a device by ID and returns 404 for a missing device', async () => {
  const { controller, calls } = setup([
    { data: device, error: null }, { data: null, error: null },
  ]);
  assert.deepEqual(await controller.getDevice(device.device_id), device);
  assert.ok(calls.some(call => call[0] === 'eq' && call[2] === device.device_id));
  await assert.rejects(controller.getDevice('missing'), error => error.getStatus() === 404);
});

test('read failures return 503 instead of an empty result or 404', async () => {
  for (const method of ['getDevices', 'getDevice']) {
    const { controller } = setup([{ data: null, error: { code: '42501' } }]);
    await assert.rejects(controller[method]('device'), error => error.getStatus() === 503);
  }
});

test('validates required fields and MAC format, trims input and normalizes MAC', async () => {
  const pipe = new ValidationPipe({ transform: true, whitelist: true });
  const metadata = { type: 'body', metatype: CreateDeviceDto };
  const normalized = await pipe.transform({
    ...device, name: ' Trạm 02 ', mac: '02:ab:cd:00:00:02',
  }, metadata);
  assert.equal(normalized.name, 'Trạm 02');
  assert.equal(normalized.mac, '02:AB:CD:00:00:02');
  for (const body of [
    {}, { ...device, device_id: ' ' }, { ...device, name: ' ' },
    { ...device, mac: 'invalid' }, { ...device, mac: 123 },
  ]) {
    await assert.rejects(pipe.transform(body, metadata), error => error.getStatus() === 400);
  }
});
