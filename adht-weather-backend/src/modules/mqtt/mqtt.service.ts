import { Injectable, Logger, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../database/supabase.service';
import { TelemetryGateway } from '../websocket/telemetry.gateway';
import { NotificationsService } from '../notifications/notifications.service';

@Injectable()
export class MqttService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(MqttService.name);
  public isConnected = false;

  constructor(
    private readonly config: ConfigService,
    private readonly supabaseService: SupabaseService,
    private readonly telemetryGateway: TelemetryGateway,
    private readonly notificationsService: NotificationsService,
  ) {}

  onModuleInit() {
    // TODO: Viết code kết nối MQTT Broker (EMQX Cloud / Mosquitto)
    // TODO: Subscribe các topic:
    //   - 'adht/weather/+/telemetry'
    //   - 'adht/weather/status'
    this.logger.log('[TODO] MqttService: Khởi tạo kết nối Broker MQTTS 8883');
  }

  onModuleDestroy() {
    // TODO: Viết code ngắt kết nối MQTT khi tắt server
  }

  publishCommand(deviceId: string, command: any): boolean {
    // TODO: Viết code phát lệnh điều khiển xuống ESP32
    // Topic: adht/weather/${deviceId}/command
    this.logger.log(`[TODO] Phát lệnh tới ${deviceId}: ${JSON.stringify(command)}`);
    return true;
  }

  publishConfig(deviceId: string, config: any): boolean {
    // TODO: Viết code phát cấu hình ngưỡng xuống NVS Flash ESP32
    // Topic: adht/weather/${deviceId}/config
    this.logger.log(`[TODO] Cập nhật cấu hình tới ${deviceId}: ${JSON.stringify(config)}`);
    return true;
  }
}
