import { Injectable, Logger } from '@nestjs/common';
import { CreateTelemetryDto } from './dto/create-telemetry.dto';
import { SupabaseService } from '../database/supabase.service';
import { TelemetryGateway } from '../websocket/telemetry.gateway';
import { NotificationsService } from '../notifications/notifications.service';

@Injectable()
export class TelemetryService {
  private readonly logger = new Logger(TelemetryService.name);

  constructor(
    private readonly supabaseService: SupabaseService,
    private readonly telemetryGateway: TelemetryGateway,
    private readonly notificationsService: NotificationsService,
  ) {}

  async processWebhook(dto: CreateTelemetryDto) {
    this.logger.log(`[TelemetryService] Tiếp nhận bản tin webhook từ: ${dto.device_id}`);

    // TODO: 1. Lưu CSDL Supabase
    await this.supabaseService.saveTelemetry(dto);

    // TODO: 2. Kiểm tra ngưỡng thiên tai & bắn Firebase FCM
    await this.notificationsService.checkAndAlert(dto);

    // TODO: 3. Phát số đo qua WebSocket cho App & Web
    this.telemetryGateway.broadcastTelemetry(dto);

    return { status: 'success', message: 'Telemetry received (Stub)' };
  }
}
