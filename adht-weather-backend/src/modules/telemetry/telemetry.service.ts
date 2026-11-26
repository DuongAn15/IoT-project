import { Injectable, Logger, NotImplementedException, Optional, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
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
    @Optional() private readonly configService?: ConfigService,
  ) {}

  async processWebhook(dto: CreateTelemetryDto) {
    const enabled = this.configService?.get<boolean>('auth.enableWebhookTelemetry') ?? false;
    if (!enabled) {
      throw new NotImplementedException('HTTP webhook telemetry ingestion is disabled');
    }

    this.logger.log(`[TelemetryService] Tiếp nhận bản tin webhook từ: ${dto.device_id}`);
    const saved = await this.supabaseService.saveTelemetry(dto);
    if (!saved) {
      throw new ServiceUnavailableException('Failed to persist telemetry');
    }

    this.telemetryGateway.broadcastTelemetry(dto);
    await this.notificationsService.checkAndAlert(dto);

    return { status: 'persisted', device_id: dto.device_id };
  }
}
