const assert = require('node:assert/strict');
const { test } = require('node:test');
const { Module } = require('@nestjs/common');
const { NestFactory } = require('@nestjs/core');
const { TelemetryGateway } = require('../dist/modules/websocket/telemetry.gateway');

test('broadcasts safely before the Socket.IO server is initialized', () => {
  const gateway = new TelemetryGateway();
  assert.doesNotThrow(() => gateway.broadcastTelemetry({}));
  assert.doesNotThrow(() => gateway.broadcastStatus({}));
});

test('Socket.IO path, broadcasts to all clients, ping ACK and disconnect', { timeout: 15000 }, async t => {
  class GatewayTestModule {}
  Module({ providers: [TelemetryGateway] })(GatewayTestModule);
  const app = await NestFactory.create(GatewayTestModule, { logger: false });
  t.after(async () => { await app.close(); });
  await app.listen(0, '127.0.0.1');
  const base = `http://127.0.0.1:${app.getHttpServer().address().port}`;
  const gateway = app.get(TelemetryGateway);

  // Exercise the actual Engine.IO / Socket.IO polling protocol, without extra dependencies.
  async function request(url, options = {}) {
    const response = await fetch(url, { ...options, signal: AbortSignal.timeout(5000) });
    assert.equal(response.status, 200);
    return response.text();
  }
  async function connect() {
    const url = `${base}/ws/telemetry/?EIO=4&transport=polling`;
    const handshake = await request(url);
    assert.equal(handshake[0], '0');
    const { sid } = JSON.parse(handshake.slice(1));
    const clientUrl = `${url}&sid=${encodeURIComponent(sid)}`;
    const send = body => request(clientUrl, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body });
    const receive = () => request(clientUrl);
    await send('40');
    const acknowledgement = await receive();
    assert.ok(acknowledgement.startsWith('40'));
    return { send, receive };
  }
  const first = await connect();
  const second = await connect();
  assert.equal(gateway.server.sockets.sockets.size, 2);
  const telemetry = {
    device_id: 'station1', temp: 31.4, humi: 68,
    rain_rate: 0, rain_total: 12.5, wind_speed: 2.1,
  };
  gateway.broadcastTelemetry(telemetry);
  const expected = `42${JSON.stringify(['telemetry', telemetry])}`;
  assert.deepEqual(await Promise.all([first.receive(), second.receive()]), [expected, expected]);

  const status = { device: 'station1', status: 'online' };
  gateway.broadcastStatus(status);
  const expectedStatus = `42${JSON.stringify(['status', status])}`;
  assert.deepEqual(await Promise.all([first.receive(), second.receive()]), [expectedStatus, expectedStatus]);

  await first.send('421["ping"]');
  assert.equal(await first.receive(), '431["pong"]');
  await first.send('41');
  await second.send('41');
  assert.equal(gateway.server.sockets.sockets.size, 0);
});
