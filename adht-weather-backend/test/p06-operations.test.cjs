const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { ConflictException, BadRequestException } = require('@nestjs/common');
const { DeviceOperationsService } = require('../dist/modules/devices/device-operations.service');
const { DevicesService } = require('../dist/modules/devices/devices.service');

test('DeviceOperationsService enforces partial merge validation, expected_version conflict, and request_id idempotency', async () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'p06-ledger-'));
  const ledgerFile = path.join(tmpDir, 'ledger.json');
  const config = {
    get(key) {
      if (key === 'OPERATION_LEDGER_FILE') return ledgerFile;
      if (key === 'auth.deviceDeployments') return { adht_weather_01: 'dep-01' };
      return undefined;
    },
  };

  try {
    const ops = new DeviceOperationsService(config);

    // Partial update: only temp_max=40 (temp_min stays default 10) -> valid, version 1
    const first = ops.createConfigOperation('adht_weather_01', {
      temp_max: 40,
      expected_version: 0,
      request_id: 'cfg-req-1',
    });
    assert.equal(first.duplicate, false);
    assert.equal(first.operation.desired_version, 1);
    assert.equal(first.mergedConfig.temp_min, 10);
    assert.equal(first.mergedConfig.temp_max, 40);

    // Idempotent retry with same request_id & payload -> returns duplicate without bumping version
    const retry = ops.createConfigOperation('adht_weather_01', {
      temp_max: 40,
      expected_version: 0,
      request_id: 'cfg-req-1',
    });
    assert.equal(retry.duplicate, true);
    assert.equal(retry.operation.operation_id, first.operation.operation_id);

    // Reusing request_id with different payload -> 409 Conflict
    assert.throws(
      () =>
        ops.createConfigOperation('adht_weather_01', {
          temp_max: 42,
          request_id: 'cfg-req-1',
        }),
      ConflictException,
    );

    // Stale expected_version -> 409 Conflict
    assert.throws(
      () =>
        ops.createConfigOperation('adht_weather_01', {
          temp_max: 35,
          expected_version: 0,
        }),
      ConflictException,
    );

    // Post-merge domain validation: temp_min=45 >= desired temp_max=40 -> 400 BadRequest
    assert.throws(
      () =>
        ops.createConfigOperation('adht_weather_01', {
          temp_min: 45,
          expected_version: 1,
        }),
      BadRequestException,
    );

    // Reload from disk -> state & version survive restart
    const reloaded = new DeviceOperationsService(config);
    const state = reloaded.getStationState('adht_weather_01');
    assert.equal(state.desired_version, 1);
    assert.equal(state.desired_config.temp_max, 40);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});

test('DeviceOperationsService validates ACK deployment_id, version, kind, expiry, and isolates reported_config per version', async () => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'p06-ack-'));
  const ledgerFile = path.join(tmpDir, 'ledger.json');
  const config = {
    get(key) {
      if (key === 'OPERATION_LEDGER_FILE') return ledgerFile;
      if (key === 'auth.deviceDeployments') return { adht_weather_01: 'dep-01', adht_weather_02: 'dep-02' };
      return undefined;
    },
  };
  const mqttCalls = [];
  const mqttMock = {
    setDeviceAckHandler(cb) {
      this.ackCb = cb;
    },
    async publishConfig(id, payload) {
      mqttCalls.push({ id, payload });
      return true;
    },
    async publishCommand(id, payload) {
      mqttCalls.push({ id, payload });
      return true;
    },
  };
  try {
    const ops = new DeviceOperationsService(config);
    const devices = new DevicesService(mqttMock, {}, config, ops);

    // Same request_id on two stations must NOT overwrite each other
    await devices.sendCommand('adht_weather_01', { cmd: 'buzzer', request_id: 'shared-req-1' });
    await devices.sendCommand('adht_weather_02', { cmd: 'led', request_id: 'shared-req-1' });
    assert.equal(devices.getOperation('adht_weather_01', 'shared-req-1').payload.cmd, 'buzzer');
    assert.equal(devices.getOperation('adht_weather_02', 'shared-req-1').payload.cmd, 'led');

    // Mismatched kind ACK ('config' ACK for 'command' operation) must be rejected
    const wrongKind = ops.handleDeviceAck('adht_weather_01', {
      request_id: 'shared-req-1',
      device_id: 'adht_weather_01',
      deployment_id: 'dep-01',
      kind: 'config',
      status: 'applied',
    });
    assert.equal(wrongKind, null);
    assert.equal(devices.getOperation('adht_weather_01', 'shared-req-1').status, 'published');

    // Create v1 (temp_max: 39), then v2 (humi_max: 80), then ACK only v1 -> reported_config must keep v1 humi_max=90
    const cfgV1 = await devices.updateConfig('adht_weather_01', { temp_max: 39 });
    assert.equal(cfgV1.status, 'published');
    assert.equal(cfgV1.desired_version, 1);

    const cfgV2 = await devices.updateConfig('adht_weather_01', { humi_max: 80 });
    assert.equal(cfgV2.desired_version, 2);

    // Mismatched deployment_id ACK must be ignored
    const ignored = ops.handleDeviceAck('adht_weather_01', {
      request_id: cfgV1.operation_id,
      device_id: 'adht_weather_01',
      deployment_id: 'dep-wrong',
      boot_id: 'boot-1',
      kind: 'config',
      status: 'persisted',
      version: 1,
    });
    assert.equal(ignored, null);
    assert.equal(devices.getOperation('adht_weather_01', cfgV1.operation_id).status, 'published');

    // Mismatched version ACK (e.g. 999 for v1) and missing version ACK must be rejected
    const missingVersion = ops.handleDeviceAck('adht_weather_01', {
      request_id: cfgV1.operation_id,
      device_id: 'adht_weather_01',
      deployment_id: 'dep-01',
      boot_id: 'boot-1',
      kind: 'config',
      status: 'applied',
    });
    assert.equal(missingVersion, null);

    const wrongVersion = ops.handleDeviceAck('adht_weather_01', {
      request_id: cfgV1.operation_id,
      device_id: 'adht_weather_01',
      deployment_id: 'dep-01',
      boot_id: 'boot-1',
      kind: 'config',
      status: 'applied',
      version: 999,
    });
    assert.equal(wrongVersion, null);
    assert.equal(devices.getOperation('adht_weather_01', cfgV1.operation_id).status, 'published');

    // Matching deployment_id & exact version ACK for v1 updates reported_config to v1 snapshot
    mqttMock.ackCb('adht_weather_01', {
      request_id: cfgV1.operation_id,
      device_id: 'adht_weather_01',
      deployment_id: 'dep-01',
      boot_id: 'boot-1',
      kind: 'config',
      status: 'applied',
      version: 1,
    });
    const op = devices.getOperation('adht_weather_01', cfgV1.operation_id);
    assert.equal(op.status, 'applied');
    assert.equal(op.ack_boot_id, 'boot-1');

    // Late publish failure must NOT overwrite device 'applied' status
    const lateFail = ops.markPublishResult('adht_weather_01', cfgV1.operation_id, false);
    assert.equal(lateFail.status, 'applied');

    // Queued operation survives restart, stays queued if publish fails, and recovers on reconnect
    const queuedCmd = ops.createCommandOperation('adht_weather_01', {
      cmd: 'led',
      arg: 'on',
      request_id: 'outbox-cmd-1',
    });
    assert.equal(queuedCmd.operation.status, 'queued');
    const reloadedOps = new DeviceOperationsService(config);
    let brokerOnline = false;
    const recoveredMqtt = {
      setDeviceAckHandler() {},
      setBrokerConnectHandler(cb) {
        this.connectCb = cb;
      },
      async publishCommand(id, payload) {
        if (!brokerOnline) return false;
        mqttCalls.push({ id, payload });
        return true;
      },
      async publishConfig() {
        return brokerOnline;
      },
    };
    const recoveredDevices = new DevicesService(recoveredMqtt, {}, config, reloadedOps);
    assert.equal(await recoveredDevices.recoverPendingOperations(), 0);
    assert.equal(reloadedOps.getOperation('adht_weather_01', 'outbox-cmd-1').status, 'queued');

    brokerOnline = true;
    recoveredMqtt.connectCb();
    await new Promise((r) => setTimeout(r, 20));
    assert.equal(reloadedOps.getOperation('adht_weather_01', 'outbox-cmd-1').status, 'published');

    // Ledger write failure must roll back RAM (desired_version and request_id)
    const unWritableConfig = {
      get(key) {
        if (key === 'OPERATION_LEDGER_FILE') return '/proc/invalid-ledger-dir/ledger.json';
        return undefined;
      },
    };
    const failingOps = new DeviceOperationsService(unWritableConfig);
    assert.throws(() =>
      failingOps.createConfigOperation('adht_weather_01', {
        temp_max: 44,
        request_id: 'rollback-cfg-1',
      }),
    );
    assert.equal(failingOps.getStationState('adht_weather_01').desired_version, 0);
    assert.throws(() => failingOps.getOperation('adht_weather_01', 'rollback-cfg-1'));

    const st = devices.getStationState('adht_weather_01');
    assert.equal(st.reported_version, 1);
    assert.equal(st.reported_config.temp_max, 39);
    assert.equal(st.reported_config.humi_max, 90);

    // Expired command cannot be completed by a late ACK
    const cmdRes = await devices.sendCommand('adht_weather_01', {
      cmd: 'buzzer',
      ttl_seconds: 5,
    });
    const opObj = ops.getOperation('adht_weather_01', cmdRes.operation_id);
    opObj.expires_at = new Date(Date.now() - 1000).toISOString();
    const expiredAck = ops.handleDeviceAck('adht_weather_01', {
      request_id: cmdRes.operation_id,
      device_id: 'adht_weather_01',
      deployment_id: 'dep-01',
      kind: 'command',
      status: 'applied',
    });
    assert.equal(expiredAck.status, 'expired');
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }
});
