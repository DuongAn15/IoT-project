import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { connect, MqttClient } from 'mqtt';
import { CreateTelemetryDto } from '../telemetry/dto/create-telemetry.dto';
import { SupabaseService } from '../database/supabase.service';
import { TelemetryGateway } from '../websocket/telemetry.gateway';
import { NotificationsService } from '../notifications/notifications.service';
import type { SendCommandDto } from '../devices/dto/send-command.dto';
import type { UpdateConfigDto } from '../devices/dto/update-config.dto';

@Injectable()
export class MqttService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MqttService.name);
  private client?: MqttClient;
  public isConnected = false;

  constructor(
    private readonly config: ConfigService,
    private readonly supabaseService: SupabaseService,
    private readonly telemetryGateway: TelemetryGateway,
    private readonly notificationsService: NotificationsService,
  ) {}

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
      clean: true,
      resubscribe: false,
    });

    this.client.on('connect', () => {
      this.isConnected = true;
      this.logger.log('Connected to MQTT broker');
      this.client.subscribe(
        ['adht/weather/+/telemetry', 'adht/weather/status'],
        { qos: 1 },
        (error, granted) => {
          if (error || !granted?.length || granted.some((subscription) => subscription.qos === 128)) {
            this.logger.error('MQTT subscribe failed; check broker permissions');
            return;
          }
          this.logger.log('Subscribed to adht/weather/+/telemetry and adht/weather/status');
        },
      );
    });

    this.client.on('message', (topic, payload) => {
      void this.handleMessage(topic, payload).catch(() => {
        this.logger.error('Failed to process MQTT message');
      });
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

  private async handleMessage(topic: string, payload: Buffer): Promise<void> {
    // chỉ cho phép 2 topic
    //  - 'adht/weather/+/telemetry'
    //   - 'adht/weather/status'
    const telemetryTopic = /^adht\/weather\/([^/]+)\/telemetry$/.exec(topic);
    if (!telemetryTopic && topic !== 'adht/weather/status') return;

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

    if (!telemetryTopic) {
      this.telemetryGateway.broadcastStatus(data);
      return;
    }

    const telemetry = plainToInstance(CreateTelemetryDto, data);
    const errors = await validate(telemetry, { whitelist: true, forbidUnknownValues: true });
    if (errors.length || telemetry.device_id !== telemetryTopic[1]) {
      this.logger.warn('Ignored MQTT telemetry: invalid fields or device ID mismatch');
      return;
    }

    this.logger.debug('Received valid MQTT telemetry');
    this.telemetryGateway.broadcastTelemetry(telemetry);
    await this.supabaseService.saveTelemetry(telemetry);
    await this.notificationsService.checkAndAlert(telemetry);
  }

  publishCommand(deviceId: string, command: SendCommandDto): Promise<boolean> {
    return this.publishToDevice(deviceId, 'command', command);
  }

  publishConfig(deviceId: string, config: UpdateConfigDto): Promise<boolean> {
    return this.publishToDevice(deviceId, 'config', config);
  }

  private async publishToDevice(
    deviceId: string,
    action: 'command' | 'config',
    payload: SendCommandDto | UpdateConfigDto,
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
