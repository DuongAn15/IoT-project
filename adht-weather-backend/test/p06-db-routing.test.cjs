const test = require('node:test');
const assert = require('node:assert/strict');
const { DevicesService } = require('../dist/modules/devices/devices.service');

test('P06 DB route keeps the same request ID across uncertain publish and device ACK', async () => {
  const operations = new Map();
  let brokerOnline = false;
  const sent = [];
  const db = {
    async createP06Operation({ deviceId, kind, payload, requestId, expiresAt }) {
      const key = `${deviceId}:${requestId}`;
      if (operations.has(key)) return { operation: operations.get(key), duplicate: true };
      const op = { device_id: deviceId, operation_id: requestId, kind, payload,
        expires_at: expiresAt, status: 'queued' };
      operations.set(key, op);
      return { operation: op, duplicate: false };
    },
    async claimP06Operations() {
      return [...operations.values()].filter(op => op.status === 'queued' || op.status === 'published');
    },
    async markP06Publish(deviceId, operationId, ok) {
      const op = operations.get(`${deviceId}:${operationId}`);
      if (ok) { op.status = 'published'; op.broker_acked_at = new Date().toISOString(); }
    },
    async getP06Operation(deviceId, operationId) {
      return operations.get(`${deviceId}:${operationId}`);
    },
    async applyP06Ack(deviceId, ack) {
      operations.get(`${deviceId}:${ack.request_id}`).status = ack.status;
    },
  };
  const mqtt = {
    setDeviceAckHandler(handler) { this.ack = handler; },
    setBrokerConnectHandler(handler) { this.connect = handler; },
    async publishCommand(deviceId, payload) {
      sent.push({ deviceId, payload });
      return brokerOnline;
    },
  };
  const service = new DevicesService(mqtt, db);
  const first = await service.sendCommand('station', { cmd: 'reboot', request_id: 'same-123' });
  assert.equal(first.status, 'queued');
  await new Promise(resolve => setImmediate(resolve));
  assert.equal((await service.sendCommand('station', { cmd: 'reboot', request_id: 'same-123' })).duplicate, true);
  brokerOnline = true;
  assert.equal(await service.recoverPendingOperations(), 1);
  assert.equal(sent[0].payload.request_id, sent[1].payload.request_id);
  // A missing device ACK causes the same ID to be published again after due claim.
  assert.equal(await service.recoverPendingOperations(), 1);
  assert.equal(sent[2].payload.request_id, 'same-123');
  mqtt.ack('station', { request_id: 'same-123', kind: 'command', status: 'applied' });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(operations.get('station:same-123').status, 'applied');
});
