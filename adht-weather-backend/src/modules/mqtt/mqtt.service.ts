import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { appendFileSync, existsSync, mkdirSync, readFileSync } from 'fs';
import { dirname } from 'path';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { connect, MqttClient } from 'mqtt';
import { CreateTelemetryDto } from '../telemetry/dto/create-telemetry.dto';
import {
  MAX_V2_PAYLOAD_BYTES,
  validateAndDeriveMinuteLogV2,
  V2ErrorCode,
} from '../telemetry/minute-log-v2';
import { SupabaseService } from '../database/supabase.service';
import { TelemetryGateway } from '../websocket/telemetry.gateway';
import { NotificationsService } from '../notifications/notifications.service';
import type { SendCommandDto } from '../devices/dto/send-command.dto';
import type { UpdateConfigDto } from '../devices/dto/update-config.dto';

interface QueuedMqttMessage {
  topic: string;
  payload: Buffer;
}

export interface V2IngestResult {
  status: 'persisted' | 'duplicate' | 'rejected';
  errorCode?: V2ErrorCode;
  retryable?: boolean;
}

@Injectable()
export class MqttService implements OnModuleInit, OnModuleDestroy {
  private static readonly MAX_QUEUE_SIZE = 200;
  private static readonly MAX_CONCURRENCY = 4;
  private static readonly MAX_DEDUP_KEYS = 1000;
  private static readonly MAX_V2_DEDUP_KEYS = 2000;

  private readonly logger = new Logger(MqttService.name);
  private client?: MqttClient;
  public isConnected = false;

  private readonly messageQueue: QueuedMqttMessage[] = [];
  private activeWorkers = 0;
  private readonly seenSamples = new Set<string>();
  private readonly seenOrder: string[] = [];
  private readonly v2LogHashes = new Map<string, string>();
  private readonly v2DedupFile?: string;

  constructor(
    private readonly config: ConfigService,
    private readonly supabaseService: SupabaseService,
    private readonly telemetryGateway: TelemetryGateway,
    private readonly notificationsService: NotificationsService,
  ) {
    this.v2DedupFile = this.config?.get?.<string>('auth.v2DedupFile');
    this.loadV2DedupJournal();
  }

  onModuleInit() {
    this.client = connect({
      protocol: this.config.getOrThrow<boolean>('mqtt.useTls') ? 'mqtts' : 'mqtt',
      host: this.config.getOrThrow<string>('mqtt.host'),
      port: this.config.getOrThrow<number>('mqtt.port'),
      username: this.config.getOrThrow<string>('mqtt.username'),
      password: this.config.get<string>('mqtt.password'),
      clientId: this.config.getOrThrow<string>('mqtt.clientId'),
      rejectUnauthorized: true,
      reconnectPeriod: 5000,
      connectTimeout: 30000,
      clean: false,
      resubscribe: true,
    });

    this.client.on('connect', () => {
      this.isConnected = true;
      this.logger.log('Connected to MQTT broker');
      this.client.subscribe(
        [
          'adht/weather/+/telemetry',
          'adht/weather/+/telemetry/log',
          'adht/weather/+/ack',
          'adht/weather/status',
        ],
        { qos: 1 },
        (error, granted) => {
          if (error || !granted?.length || granted.some((subscription) => subscription.qos === 128)) {
            this.logger.error('MQTT subscribe failed; check broker permissions');
            return;
          }
          this.logger.log('Subscribed to telemetry (v1/v2) and status topics');
        },
      );
    });

    this.client.on('message', (topic, payload) => {
      this.enqueueMessage(topic, payload);
    });
    this.client.on('error', (error) => {
      this.logger.error(`MQTT error: ${error.message}`);
    });
    this.client.on('offline', () => {
      this.isConnected = false;
    });
    this.client.on('close', () => {
      this.isConnected = false;
    });
    this.client.on('reconnect', () => {
      this.logger.log('Reconnecting to MQTT broker');
    });
  }

  async onModuleDestroy(): Promise<void> {
    this.isConnected = false;
    if (this.client) {
      await this.client.endAsync(true);
    }
  }

  enqueueMessage(topic: string, payload: Buffer): boolean {
    if (this.messageQueue.length >= MqttService.MAX_QUEUE_SIZE) {
      this.logger.warn('MQTT ingestion queue full; dropping incoming message');
      return false;
    }
    this.messageQueue.push({ topic, payload });
    this.drainQueue();
    return true;
  }

  private drainQueue(): void {
    while (this.activeWorkers < MqttService.MAX_CONCURRENCY && this.messageQueue.length > 0) {
      const next = this.messageQueue.shift();
      if (!next) break;
      this.activeWorkers++;
      void this.handleMessage(next.topic, next.payload)
        .catch(() => {
          this.logger.error('Failed to process MQTT message');
        })
        .finally(() => {
          this.activeWorkers--;
          this.drainQueue();
        });
    }
  }

  private getDedupKey(telemetry: CreateTelemetryDto): string | null {
    if (telemetry.sample_id?.trim()) {
      return `sample:${telemetry.device_id}:${telemetry.sample_id.trim()}`;
    }
    if (telemetry.boot_id?.trim() && telemetry.sequence !== undefined) {
      return `seq:${telemetry.device_id}:${telemetry.boot_id.trim()}:${telemetry.sequence}`;
    }
    if (telemetry.timestamp !== undefined) {
      return `ts:${telemetry.device_id}:${telemetry.timestamp}`;
    }
    return null;
  }

  private isDuplicateSample(key: string): boolean {
    if (this.seenSamples.has(key)) {
      return true;
    }
    this.seenSamples.add(key);
    this.seenOrder.push(key);
    if (this.seenOrder.length > MqttService.MAX_DEDUP_KEYS) {
      const oldest = this.seenOrder.shift();
      if (oldest) {
        this.seenSamples.delete(oldest);
      }
    }
    return false;
  }

  private loadV2DedupJournal(): void {
    if (!this.v2DedupFile || !existsSync(this.v2DedupFile)) return;
    try {
      const lines = readFileSync(this.v2DedupFile, 'utf8').split('\n');
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        const parsed = JSON.parse(trimmed) as { key?: string; hash?: string };
        if (parsed.key && parsed.hash) {
          this.setV2HashInMemory(parsed.key, parsed.hash);
        }
      }
    } catch {
      this.logger.warn('Failed to load v2 dedup journal; starting with empty in-memory map');
    }
  }

  private setV2HashInMemory(identityKey: string, payloadHash: string): void {
    this.v2LogHashes.set(identityKey, payloadHash);
    if (this.v2LogHashes.size > MqttService.MAX_V2_DEDUP_KEYS) {
      const oldestKey = this.v2LogHashes.keys().next().value;
      if (oldestKey) {
        this.v2LogHashes.delete(oldestKey);
      }
    }
  }

  private recordV2Hash(identityKey: string, payloadHash: string): void {
    this.setV2HashInMemory(identityKey, payloadHash);
    if (this.v2DedupFile) {
      try {
        mkdirSync(dirname(this.v2DedupFile), { recursive: true });
        appendFileSync(
          this.v2DedupFile,
          `${JSON.stringify({ key: identityKey, hash: payloadHash })}\n`,
        );
      } catch {
        this.logger.warn('Failed to append to v2 dedup journal');
      }
    }
  }

  async processMinuteLogV2(topicDeviceId: string, raw: unknown): Promise<V2IngestResult> {
    const deployments = this.config?.get?.<Record<string, string>>('auth.deviceDeployments');
    const nodeEnv = this.config?.get?.<string>('nodeEnv') || process.env.NODE_ENV || 'development';
    const expectedDeploymentId = deployments?.[topicDeviceId];

    if (nodeEnv === 'production' && !expectedDeploymentId) {
      this.logger.warn(
        `Rejected MQTT v2 minute_log (identity_mismatch): no DEVICE_DEPLOYMENTS binding for ${topicDeviceId}`,
      );
      return {
        status: 'rejected',
        errorCode: 'identity_mismatch',
        retryable: false,
      };
    }

    const validated = validateAndDeriveMinuteLogV2(
      raw,
      topicDeviceId,
      new Date(),
      expectedDeploymentId,
    );
    if ('error' in validated) {
      this.logger.warn(
        `Rejected MQTT v2 minute_log (${validated.error.code}): ${validated.error.message}`,
      );
      return {
        status: 'rejected',
        errorCode: validated.error.code,
        retryable: validated.error.retryable,
      };
    }

    const { record } = validated;
    const hasDbV2Persistence = typeof this.supabaseService.saveMinuteLogV2 === 'function';

    if (hasDbV2Persistence) {
      // Database unique constraint (weather_logs_v2) is the single source of truth.
      const dbResult = await this.supabaseService.saveMinuteLogV2(record);
      if (dbResult === 'duplicate') {
        return { status: 'duplicate' };
      }
      if (dbResult === 'conflict') {
        this.logger.warn(
          `Conflict in DB on v2 minute_log identity ${record.identityKey}; keeping original record`,
        );
        return { status: 'rejected', errorCode: 'conflict', retryable: false };
      }
      if (dbResult === 'error') {
        this.logger.warn(`Failed to persist v2 minute_log ${record.identityKey}`);
        return { status: 'rejected', errorCode: 'storage_unavailable', retryable: true };
      }
    } else {
      const existingHash = this.v2LogHashes.get(record.identityKey);
      if (existingHash !== undefined) {
        if (existingHash === record.payloadHash) {
          this.logger.debug(`Ignored duplicate v2 minute_log: ${record.identityKey}`);
          return { status: 'duplicate' };
        }
        this.logger.warn(
          `Conflict on v2 minute_log identity ${record.identityKey}; keeping original record`,
        );
        return { status: 'rejected', errorCode: 'conflict', retryable: false };
      }

      const saved = await this.supabaseService.saveTelemetry({
        device_id: record.device_id,
        temp: record.temp,
        humi: record.humi,
        rain_rate: record.rain_rate,
        wind_speed: record.wind_speed,
        recorded_at: record.recorded_at,
      });

      if (!saved) {
        this.logger.warn(`Failed to persist v2 minute_log ${record.identityKey}`);
        return { status: 'rejected', errorCode: 'storage_unavailable', retryable: true };
      }
      this.recordV2Hash(record.identityKey, record.payloadHash);
    }

    await this.notificationsService.checkAndAlert({
      device_id: record.device_id,
      temp: record.temp,
      humi: record.humi,
      rain_rate: record.rain_rate,
      wind_speed: record.wind_speed,
    });

    return { status: 'persisted' };
  }

  async handleMessage(topic: string, payload: Buffer): Promise<void> {
    if (payload.length > MAX_V2_PAYLOAD_BYTES) {
      this.logger.warn(`Ignored oversized MQTT payload (${payload.length} bytes) on ${topic}`);
      return;
    }

    const v1TelemetryTopic = /^adht\/weather\/([^/]+)\/telemetry$/.exec(topic);
    const v2MinuteLogTopic = /^adht\/weather\/([^/]+)\/telemetry\/log$/.exec(topic);
    const ackTopic = /^adht\/weather\/([^/]+)\/ack$/.exec(topic);
    if (!v1TelemetryTopic && !v2MinuteLogTopic && !ackTopic && topic !== 'adht/weather/status') return;

    let data: unknown;
    try {
      data = JSON.parse(payload.toString());
    } catch {
      this.logger.warn('Ignored MQTT message: invalid JSON');
      return;
    }
    if (typeof data !== 'object' || data === null || Array.isArray(data)) {
      this.logger.warn('Ignored MQTT message: expected a JSON object');
      return;
    }

    if (topic === 'adht/weather/status') {
      this.telemetryGateway.broadcastStatus(data);
      return;
    }

    if (v2MinuteLogTopic) {
      await this.processMinuteLogV2(v2MinuteLogTopic[1], data);
      return;
    }

    if (ackTopic) {
      this.deviceAckHandler?.(ackTopic[1], data as Record<string, unknown>);
      return;
    }

    const telemetry = plainToInstance(CreateTelemetryDto, data);
    const errors = await validate(telemetry, { whitelist: true, forbidUnknownValues: true });
    if (errors.length || telemetry.device_id !== v1TelemetryTopic![1]) {
      this.logger.warn('Ignored MQTT telemetry: invalid fields or device ID mismatch');
      return;
    }

    const dedupKey = this.getDedupKey(telemetry);
    if (dedupKey && this.isDuplicateSample(dedupKey)) {
      this.logger.debug(`Ignored duplicate MQTT telemetry: ${dedupKey}`);
      return;
    }

    this.logger.debug('Received valid MQTT telemetry');
    const v2CutoverEnabled = this.config?.get?.<boolean>('auth.v2CutoverEnabled') ?? false;
    if (!v2CutoverEnabled) {
      const saved = await this.supabaseService.saveTelemetry(telemetry);
      if (!saved) {
        this.logger.warn(`Skipped broadcast/alert because persistence failed for ${telemetry.device_id}`);
        return;
      }
    }
    this.telemetryGateway.broadcastTelemetry(telemetry);
    await this.notificationsService.checkAndAlert(telemetry);
  }

  private deviceAckHandler?: (deviceId: string, payload: Record<string, unknown>) => void;

  setDeviceAckHandler(handler: (deviceId: string, payload: Record<string, unknown>) => void): void {
    this.deviceAckHandler = handler;
  }

  publishCommand(deviceId: string, command: SendCommandDto | Record<string, unknown>): Promise<boolean> {
    return this.publishToDevice(deviceId, 'command', command);
  }

  publishConfig(deviceId: string, config: UpdateConfigDto | Record<string, unknown>): Promise<boolean> {
    return this.publishToDevice(deviceId, 'config', config);
  }

  private async publishToDevice(
    deviceId: string,
    action: 'command' | 'config',
    payload: SendCommandDto | UpdateConfigDto | Record<string, unknown>,
  ): Promise<boolean> {
    if (!deviceId.trim() || /[/+#\u0000]/.test(deviceId)) {
      this.logger.warn('Cannot publish MQTT message: invalid device ID');
      return false;
    }

    const client = this.client;
    if (!this.isConnected || !client?.connected) {
      this.logger.warn('Cannot publish MQTT message: broker disconnected');
      return false;
    }

    try {
      // ACK confirms broker receipt, not execution by the device.
      await client.publishAsync(
        `adht/weather/${deviceId}/${action}`,
        JSON.stringify(payload),
        { qos: 1, retain: false },
      );
      this.logger.log(`MQTT ${action} acknowledged by broker`);
      return true;
    } catch {
      this.logger.error(`Failed to publish MQTT ${action}`);
      return false;
    }
  }
}
