const assert = require('node:assert/strict');
const { test } = require('node:test');
const { MqttService } = require('../dist/modules/mqtt/mqtt.service');
const { DevicesService } = require('../dist/modules/devices/devices.service');

function createService(publishAsync) {
  const service = new MqttService({}, {}, {}, {});
  service.client = { connected: true, publishAsync };
  service.isConnected = true;
  return service;
}

test('publishes command and config JSON on device-specific topics', async () => {
  const publications = [];
  const service = createService(async (...args) => { publications.push(args); });
  assert.equal(await service.publishCommand('station1', { cmd: 'buzzer', arg: '500' }), true);
  assert.equal(await service.publishConfig('station1', { temp_max: 38, buzzer: false }), true);
  assert.deepEqual(publications, [
    ['adht/weather/station1/command', '{"cmd":"buzzer","arg":"500"}', { qos: 1, retain: false }],
    ['adht/weather/station1/config', '{"temp_max":38,"buzzer":false}', { qos: 1, retain: false }],
  ]);
});

test('rejects disconnected clients and invalid device IDs without publishing', async () => {
  let publications = 0;
  const service = createService(async () => { publications++; });
  for (const id of ['', ' ', 'a/b', '+', '#', 'a\0b']) {
    assert.equal(await service.publishCommand(id, { cmd: 'reboot' }), false);
  }
  service.client.connected = false;
  assert.equal(await service.publishConfig('station1', { buzzer: false }), false);
  service.client = undefined;
  assert.equal(await service.publishCommand('station1', { cmd: 'reboot' }), false);
  assert.equal(publications, 0);
});

test('waits for broker ACK before returning success', async () => {
  let acknowledge;
  const service = createService(() => new Promise(resolve => { acknowledge = resolve; }));
  const devices = new DevicesService(service);
  let settled = false;
  const result = devices.sendCommand('station1', { cmd: 'buzzer' });
  void result.then(() => { settled = true; });
  await Promise.resolve();
  assert.equal(settled, false);
  acknowledge();
  assert.equal((await result).status, 'success');
});

test('reports failed status when broker rejects publication', async () => {
  const service = createService(async () => { throw new Error('publish failed'); });
  const devices = new DevicesService(service);
  assert.equal((await devices.sendCommand('station1', { cmd: 'buzzer' })).status, 'failed');
  assert.equal((await devices.updateConfig('station1', { temp_max: 38 })).status, 'failed');
});
