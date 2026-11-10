const assert = require('node:assert/strict');
const Module = require('node:module');
const { test } = require('node:test');

let apps = [];
let initializationCount = 0;
let deleted = [];
let messaging;
let credentialFailure = false;
let certArgs = [];
const originalLoad = Module._load;
let NotificationsService;
try {
  Module._load = function (name, ...args) {
    if (name === 'firebase-admin/app') return {
      getApps: () => apps,
      // credential là đường dẫn file (local) hoặc object service account (từ FIREBASE_CREDENTIALS_JSON).
      cert: credential => {
        certArgs.push(credential);
        if (typeof credential === 'string') assert.equal(credential, 'fake-credentials.json');
        if (credentialFailure) throw new Error('private-key-material');
        return {};
      },
      initializeApp: (options, name) => { initializationCount++; return { name }; },
      deleteApp: async app => { deleted.push(app); },
    };
    if (name === 'firebase-admin/messaging') return { getMessaging: () => messaging };
    return originalLoad.call(this, name, ...args);
  };
  ({ NotificationsService } = require('../dist/modules/notifications/notifications.service'));
} finally {
  Module._load = originalLoad;
}

function setup(overrides = {}) {
  apps = [];
  deleted = [];
  credentialFailure = false;
  const sent = [];
  const subscriptions = [];
  messaging = {
    send: async message => { sent.push(message); return 'message-id'; },
    subscribeToTopic: async (...args) => {
      subscriptions.push(args);
      return { successCount: 1, failureCount: 0, errors: [] };
    },
  };
  const values = {
    'firebase.alertTopic': 'adht_weather_alerts',
    'firebase.credentialsPath': 'fake-credentials.json',
    thresholds: { tempMax: 38, tempMin: 10, humiMax: 90, windMax: 15, rainMax: 30 },
    ...overrides,
  };
  // Service gọi cả get() (credentialsJson tùy chọn) lẫn getOrThrow() như ConfigService thật.
  const config = { get: key => values[key], getOrThrow: key => values[key] };
  const service = new NotificationsService(config);
  const logs = [];
  service.logger = { warn: message => logs.push(message), error: message => logs.push(message) };
  return { service, sent, subscriptions, logs, config };
}

const normal = { device_id: 'station1', temp: 25, humi: 60, wind_speed: 2, rain_rate: 0 };

test('initializes Firebase, subscribes token and sends topic messages without returning token', async () => {
  const { service, subscriptions, sent } = setup();
  const result = await service.registerToken('private-token');
  assert.equal(result.status, 'success');
  assert.doesNotMatch(JSON.stringify(result), /private-token/);
  assert.deepEqual(subscriptions, [[['private-token'], 'adht_weather_alerts']]);
  await service.sendPushNotification('Title', 'Body', { device_id: 'station1' });
  assert.deepEqual(sent[0], { topic: 'adht_weather_alerts', notification: { title: 'Title', body: 'Body' }, data: { device_id: 'station1' } });
  await service.onModuleDestroy();
  assert.equal(deleted.length, 1);
});

test('loads credentials from FIREBASE_CREDENTIALS_JSON as raw JSON or base64 before the file path', () => {
  const account = { project_id: 'demo', client_email: 'a@demo.iam', private_key: 'key' };
  for (const credentialsJson of [JSON.stringify(account), Buffer.from(JSON.stringify(account)).toString('base64')]) {
    certArgs = [];
    setup({ 'firebase.credentialsJson': credentialsJson });
    assert.deepEqual(certArgs, [account]);
  }
  certArgs = [];
  setup();
  assert.deepEqual(certArgs, ['fake-credentials.json']);
});

test('normal readings send nothing; all configured threshold boundaries are inclusive', async () => {
  const { service, sent } = setup();
  await service.checkAndAlert(normal);
  assert.equal(sent.length, 0);
  await service.checkAndAlert({ ...normal, temp: 38, humi: 90, wind_speed: 15, rain_rate: 30 });
  assert.deepEqual(sent.map(message => message.data.alert_type).sort(), ['HIGH_TEMP', 'HIGH_HUMIDITY', 'STRONG_WIND', 'HEAVY_RAIN'].sort());
  await service.checkAndAlert({ ...normal, temp: 10 });
  assert.equal(sent.at(-1).data.alert_type, 'LOW_TEMP');
  for (const message of sent) assert.ok(Object.values(message.data).every(value => typeof value === 'string'));
});

test('cooldown is per station and alert type and expires after five minutes', async () => {
  const originalNow = Date.now;
  let now = 1000000;
  Date.now = () => now;
  try {
    const { service, sent } = setup();
    const hot = { ...normal, temp: 40 };
    await service.checkAndAlert(hot);
    now += 299999;
    await service.checkAndAlert(hot);
    assert.equal(sent.length, 1);
    await service.checkAndAlert({ ...hot, device_id: 'station2' });
    assert.equal(sent.length, 2);
    now++;
    await service.checkAndAlert(hot);
    assert.equal(sent.length, 3);
  } finally { Date.now = originalNow; }
});

test('concurrent readings cannot send duplicates, and failed sends can retry', async () => {
  const { service, sent } = setup();
  const hot = { ...normal, temp: 40 };
  let release;
  messaging.send = () => new Promise(resolve => { release = resolve; });
  const first = service.checkAndAlert(hot);
  await service.checkAndAlert(hot);
  release('ok');
  await first;
  assert.equal(service.alerts.size, 1);
  service.alerts.clear();
  messaging.send = async () => { throw new Error('private-token'); };
  await service.checkAndAlert(hot);
  assert.equal(service.alerts.size, 0);
  messaging.send = async message => { sent.push(message); };
  await service.checkAndAlert(hot);
  assert.equal(sent.length, 1);
});

test('handles invalid tokens and Firebase failures without leaking credentials', async () => {
  const { service, logs } = setup();
  await assert.rejects(service.registerToken(' '), error => error.getStatus() === 400);
  messaging.subscribeToTopic = async () => ({ successCount: 0, failureCount: 1, errors: [{ error: { code: 'messaging/registration-token-not-registered' } }] });
  await assert.rejects(service.registerToken('private-token'), error => error.getStatus() === 400);
  messaging.subscribeToTopic = async () => { throw new Error('private-token'); };
  await assert.rejects(service.registerToken('private-token'), error => error.getStatus() === 503);
  messaging.send = async () => { throw new Error('private-key-material'); };
  await assert.rejects(service.sendPushNotification('Title', 'Body'), error => error.getStatus() === 503);
  assert.doesNotMatch(logs.join('\n'), /private-token|private-key-material/);
});

test('reuses existing app without deleting it and sanitizes credential failures', async () => {
  const { config } = setup();
  apps = [{ name: 'adht-weather-notifications' }];
  const count = initializationCount;
  const service = new NotificationsService(config);
  assert.equal(initializationCount, count);
  await service.onModuleDestroy();
  assert.equal(deleted.length, 0);
  apps = [];
  credentialFailure = true;
  assert.throws(() => new NotificationsService(config), error => !error.message.includes('private-key-material') && error.message.includes('FIREBASE_CREDENTIALS_PATH'));
});

test('rejects invalid topic configuration and ignores malformed telemetry', async () => {
  assert.throws(() => setup({ 'firebase.alertTopic': '/topics/alerts' }), /Invalid FIREBASE_ALERT_TOPIC/);
  const { service, sent } = setup();
  await service.checkAndAlert({ ...normal, temp: NaN });
  await service.checkAndAlert({ ...normal, device_id: '' });
  assert.equal(sent.length, 0);
});
