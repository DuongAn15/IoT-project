const assert = require('node:assert/strict');
const { test } = require('node:test');
const {
  BadRequestException,
  ForbiddenException,
  NotImplementedException,
  UnauthorizedException,
} = require('@nestjs/common');
const { plainToInstance } = require('class-transformer');
const { validate } = require('class-validator');
const loadConfiguration = require('../dist/config/configuration').default;
const { ApiAuthGuard } = require('../dist/common/guards/api-auth.guard');
const { MqttService } = require('../dist/modules/mqtt/mqtt.service');
const { TelemetryService } = require('../dist/modules/telemetry/telemetry.service');
const { TelemetryGateway } = require('../dist/modules/websocket/telemetry.gateway');
const { DevicesService } = require('../dist/modules/devices/devices.service');
const { WeatherService } = require('../dist/modules/weather/weather.service');
const { SendCommandDto } = require('../dist/modules/devices/dto/send-command.dto');
const { UpdateConfigDto } = require('../dist/modules/devices/dto/update-config.dto');

test('supabase config never falls back to SUPABASE_ANON_KEY', () => {
  const prevService = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const prevKey = process.env.SUPABASE_KEY;
  const prevAnon = process.env.SUPABASE_ANON_KEY;
  try {
    delete process.env.SUPABASE_SERVICE_ROLE_KEY;
    delete process.env.SUPABASE_KEY;
    process.env.SUPABASE_ANON_KEY = 'anon-should-not-be-used';
    const cfg = loadConfiguration();
    assert.equal(cfg.supabase.key, '');
  } finally {
    if (prevService !== undefined) process.env.SUPABASE_SERVICE_ROLE_KEY = prevService;
    if (prevKey !== undefined) process.env.SUPABASE_KEY = prevKey;
    if (prevAnon !== undefined) process.env.SUPABASE_ANON_KEY = prevAnon;
    else delete process.env.SUPABASE_ANON_KEY;
  }
});

test('ApiAuthGuard enforces Bearer / x-api-key token when configured', () => {
  const config = {
    get: (key) => (key === 'auth.apiToken' ? 'secret-token-123' : 'production'),
  };
  const guard = new ApiAuthGuard(config);
  const makeCtx = (headers) => ({
    switchToHttp: () => ({ getRequest: () => ({ headers }) }),
  });

  assert.throws(() => guard.canActivate(makeCtx({})), UnauthorizedException);
  assert.throws(
    () => guard.canActivate(makeCtx({ authorization: 'Bearer wrong' })),
    UnauthorizedException,
  );
  assert.equal(guard.canActivate(makeCtx({ authorization: 'Bearer secret-token-123' })), true);
  assert.equal(guard.canActivate(makeCtx({ 'x-api-key': 'secret-token-123' })), true);
});

test('MqttService deduplicates telemetry and skips broadcast when saveTelemetry fails', async () => {
  let savedCalls = 0;
  let broadcastCalls = 0;
  let alertCalls = 0;
  let saveResult = true;

  const service = new MqttService(
    {},
    { saveTelemetry: async () => { savedCalls++; return saveResult; } },
    { broadcastTelemetry: () => { broadcastCalls++; } },
    { checkAndAlert: async () => { alertCalls++; } },
  );

  const payload = Buffer.from(JSON.stringify({
    device_id: 'adht_weather_01',
    boot_id: 'boot1',
    sequence: 1,
    sample_id: 'adht_weather_01:boot1:1',
    temp: 28.5,
    humi: 70,
    rain_rate: 0,
    rain_total: 0,
    wind_speed: 2.0,
  }));

  await service.handleMessage('adht/weather/adht_weather_01/telemetry', payload);
  await service.handleMessage('adht/weather/adht_weather_01/telemetry', payload);
  assert.equal(savedCalls, 1);
  assert.equal(broadcastCalls, 1);
  assert.equal(alertCalls, 1);

  saveResult = false;
  const payload2 = Buffer.from(JSON.stringify({
    device_id: 'adht_weather_01',
    boot_id: 'boot1',
    sequence: 2,
    sample_id: 'adht_weather_01:boot1:2',
    temp: 29.0,
    humi: 72,
    rain_rate: 0,
    rain_total: 0,
    wind_speed: 2.5,
  }));
  await service.handleMessage('adht/weather/adht_weather_01/telemetry', payload2);
  assert.equal(savedCalls, 2);
  assert.equal(broadcastCalls, 1);
});

test('TelemetryService throws NotImplementedException when webhook ingestion is disabled', async () => {
  const svc = new TelemetryService({}, {}, {}, { get: () => false });
  await assert.rejects(
    () => svc.processWebhook({ device_id: 'adht_weather_01', temp: 25, humi: 60, rain_rate: 0, rain_total: 0, wind_speed: 1 }),
    NotImplementedException,
  );
});

test('TelemetryGateway disconnects unauthorized socket when API_AUTH_TOKEN is configured', () => {
  const config = {
    get: (key) => (key === 'auth.apiToken' ? 'ws-secret' : 'production'),
  };
  const gateway = new TelemetryGateway(config);
  let disconnected = false;
  gateway.handleConnection({
    id: 'client-1',
    handshake: { auth: { token: 'wrong' }, headers: {} },
    disconnect: (close) => { disconnected = close; },
  });
  assert.equal(disconnected, true);
});

test('SendCommandDto and UpdateConfigDto reject invalid enums and out-of-range domain values', async () => {
  const badCmd = plainToInstance(SendCommandDto, { cmd: 'arbitrary_shell' });
  assert.ok((await validate(badCmd)).length > 0);

  const badCfg = plainToInstance(UpdateConfigDto, { temp_max: 999, humi_max: 150 });
  assert.ok((await validate(badCfg)).length >= 2);
});

test('DevicesService rejects empty config, temp_min >= temp_max, invalid args, and disallowed devices', async () => {
  const mqtt = { publishCommand: async () => true, publishConfig: async () => true };
  const config = { get: (key) => (key === 'auth.allowedDevices' ? ['adht_weather_01'] : undefined) };
  const svc = new DevicesService(mqtt, {}, config);

  await assert.rejects(() => svc.updateConfig('adht_weather_01', {}), BadRequestException);
  await assert.rejects(
    () => svc.updateConfig('adht_weather_01', { temp_min: 30, temp_max: 25 }),
    BadRequestException,
  );
  await assert.rejects(
    () => svc.sendCommand('adht_weather_01', { cmd: 'buzzer', arg: 'not-a-number' }),
    BadRequestException,
  );
  await assert.rejects(
    () => svc.sendCommand('adht_weather_02', { cmd: 'reboot' }),
    ForbiddenException,
  );
});

test('DevicesService.getDevices and WeatherService filter/enforce ALLOWED_DEVICE_IDS', async () => {
  const config = { get: (key) => (key === 'auth.allowedDevices' ? ['adht_weather_01'] : undefined) };
  const devices = new DevicesService(
    {},
    {
      getDevices: async () => [
        { device_id: 'adht_weather_01', name: 'Station 1', mac: 'AA:BB:CC:DD:EE:01' },
        { device_id: 'adht_weather_02', name: 'Station 2', mac: 'AA:BB:CC:DD:EE:02' },
      ],
    },
    config,
  );
  const list = await devices.getDevices();
  assert.deepEqual(list.map((d) => d.device_id), ['adht_weather_01']);

  const weather = new WeatherService(
    { getLatest: async (id) => ({ device_id: id }), getHistory: async () => [] },
    config,
  );
  assert.deepEqual(await weather.getLatest('adht_weather_01'), { device_id: 'adht_weather_01' });
  await assert.rejects(() => weather.getLatest('adht_weather_02'), ForbiddenException);
  await assert.rejects(() => weather.getHistory('adht_weather_02', '24h'), ForbiddenException);
});
