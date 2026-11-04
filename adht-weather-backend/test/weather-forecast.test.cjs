const assert = require('node:assert/strict');
const { test } = require('node:test');
const axios = require('axios');
const { WeatherService } = require('../dist/modules/weather/weather.service');
const { WeatherController } = require('../dist/modules/weather/weather.controller');
const { buildForecast } = require('../dist/modules/weather/utils/forecast.helpers');

const NOW = Date.parse('2026-11-04T18:00:00.000Z'); // Nov 5 at 01:00 in UTC+7.
function fixture() {
  return {
    cod: '200', city: { timezone: 25200 },
    list: Array.from({ length: 40 }, (_, index) => ({
      dt: NOW / 1000 + index * 10800,
      main: { temp: 27, temp_min: 25, temp_max: 30, humidity: 70 },
      wind: { speed: 3 },
      weather: [{ description: 'mưa nhẹ', icon: '10d' }],
      pop: 0.5, rain: { '3h': 1.5 },
    })),
  };
}
function service(settings = {}) {
  const values = { 'openWeather.apiKey': 'private-key', 'openWeather.defaultLat': 10, 'openWeather.defaultLon': 106, ...settings };
  const config = { get: key => values[key], getOrThrow: key => values[key] };
  const result = new WeatherService(config, {});
  result.logger = { error() {}, warn() {} };
  return result;
}

test('groups three future local calendar days and aggregates 3-hour periods', () => {
  const { timezone, days } = buildForecast(fixture(), NOW);
  assert.equal(timezone, 25200);
  assert.deepEqual(days.map(day => day.date), ['2026-11-06', '2026-11-07', '2026-11-08']);
  for (const day of days) {
    assert.equal(day.periods.length, 8);
    assert.equal(day.temp_min, 25);
    assert.equal(day.temp_max, 30);
    assert.equal(day.humidity, 70);
    assert.equal(day.wind_speed, 3);
    assert.equal(day.rain_mm, 12);
    assert.equal(day.precipitation_probability, 0.5);
  }
});

test('missing rain means zero; malformed and incomplete responses are rejected', () => {
  const data = fixture();
  for (const item of data.list) delete item.rain;
  assert.equal(buildForecast(data, NOW).days[0].rain_mm, 0);
  assert.throws(() => buildForecast({}, NOW));
  assert.throws(() => buildForecast({ ...data, list: data.list.slice(0, 8) }, NOW), /Incomplete/);
  data.list[9].main.temp = 'invalid';
  assert.throws(() => buildForecast(data, NOW), /Invalid/);
});

test('uses metric units, Vietnamese descriptions, timeout and zero coordinates', async t => {
  const originalNow = Date.now;
  Date.now = () => NOW;
  t.after(() => { Date.now = originalNow; });
  const mocked = t.mock.method(axios, 'get', async () => ({ data: fixture() }));
  const result = await service().getForecast(0, 0);
  assert.deepEqual(result.coords, { lat: 0, lon: 0 });
  assert.equal(result.forecast_days.length, 3);
  assert.equal(result.timezone_offset_seconds, 25200);
  assert.doesNotMatch(JSON.stringify(result), /private-key/);
  const [url, options] = mocked.mock.calls[0].arguments;
  assert.equal(url, 'https://api.openweathermap.org/data/2.5/forecast');
  assert.deepEqual(options.params, { lat: 0, lon: 0, appid: 'private-key', units: 'metric', lang: 'vi' });
  assert.equal(options.timeout, 10000);
  assert.equal(options.maxRedirects, 0);
  mocked.mock.restore();
});

test('uses configured defaults only when coordinates are omitted', async t => {
  const originalNow = Date.now;
  Date.now = () => NOW;
  t.after(() => { Date.now = originalNow; });
  const mocked = t.mock.method(axios, 'get', async () => ({ data: fixture() }));
  assert.deepEqual((await service().getForecast()).coords, { lat: 10, lon: 106 });
  mocked.mock.restore();
});

test('rejects invalid coordinates and missing API key without making a request', async t => {
  const mocked = t.mock.method(axios, 'get', async () => { throw new Error('Unexpected request'); });
  const weather = service();
  for (const [lat, lon] of [[91, 0], [0, -181], [NaN, 0], [0, Infinity]]) {
    await assert.rejects(weather.getForecast(lat, lon), error => error.getStatus() === 400);
  }
  await assert.rejects(service({ 'openWeather.apiKey': '' }).getForecast(), error => error.getStatus() === 503);
  assert.equal(mocked.mock.callCount(), 0);
  mocked.mock.restore();
});

test('upstream errors are sanitized and mapped to appropriate HTTP failures', async t => {
  for (const [status, expected] of [[401, 503], [403, 503], [429, 503], [500, 502]]) {
    const mocked = t.mock.method(axios, 'get', async () => {
      throw { isAxiosError: true, response: { status }, config: { params: { appid: 'private-key' } } };
    });
    await assert.rejects(service().getForecast(), error => error.getStatus() === expected && !error.message.includes('private-key'));
    mocked.mock.restore();
  }
  const mocked = t.mock.method(axios, 'get', async () => { throw new Error('timeout private-key'); });
  await assert.rejects(service().getForecast(), error => error.getStatus() === 502 && !error.message.includes('private-key'));
  mocked.mock.restore();
});

test('controller parses query strings, including zero, and does not silently default empty or repeated values', () => {
  const calls = [];
  const controller = new WeatherController({ getForecast: (...args) => calls.push(args) });
  controller.getForecast('0', '0');
  controller.getForecast();
  controller.getForecast('', 'invalid');
  controller.getForecast(['1', '2'], '106');
  assert.deepEqual(calls[0], [0, 0]);
  assert.deepEqual(calls[1], [undefined, undefined]);
  assert.ok(Number.isNaN(calls[2][0]) && Number.isNaN(calls[2][1]));
  assert.ok(Number.isNaN(calls[3][0]));
});

test('environment defaults preserve valid zero coordinates', () => {
  const previousLat = process.env.DEFAULT_LAT;
  const previousLon = process.env.DEFAULT_LON;
  try {
    process.env.DEFAULT_LAT = '0';
    process.env.DEFAULT_LON = '0';
    const configuration = require('../dist/config/configuration').default();
    assert.equal(configuration.openWeather.defaultLat, 0);
    assert.equal(configuration.openWeather.defaultLon, 0);
  } finally {
    if (previousLat === undefined) delete process.env.DEFAULT_LAT;
    else process.env.DEFAULT_LAT = previousLat;
    if (previousLon === undefined) delete process.env.DEFAULT_LON;
    else process.env.DEFAULT_LON = previousLon;
  }
});
