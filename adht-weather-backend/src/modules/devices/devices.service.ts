import { Injectable, Logger } from '@nestjs/common';
import { MqttService } from '../mqtt/mqtt.service';
import { SendCommandDto } from './dto/send-command.dto';
import { UpdateConfigDto } from './dto/update-config.dto';
import { CreateDeviceDto } from './dto/create-device.dto';
import { SupabaseService } from '../database/supabase.service';

@Injectable()
export class DevicesService {
  private readonly logger = new Logger(DevicesService.name);

  constructor(
    private readonly mqttService: MqttService,
    private readonly supabaseService: SupabaseService,
  ) {}

  createDevice(dto: CreateDeviceDto) {
    return this.supabaseService.createDevice(dto);
  }

  getDevices() {
    return this.supabaseService.getDevices();
  }

  getDevice(deviceId: string) {
    return this.supabaseService.getDevice(deviceId);
  }

  async sendCommand(deviceId: string, dto: SendCommandDto) {
    this.logger.log(`[DevicesService] Nhận lệnh điều khiển cho trạm ${deviceId}: ${dto.cmd}`);
    const success = await this.mqttService.publishCommand(deviceId, dto);
    return {
      status: success ? 'success' : 'failed',
      deviceId,
      command: dto,
    };
  }

  async updateConfig(deviceId: string, dto: UpdateConfigDto) {
    this.logger.log(`[DevicesService] Nhận cấu hình mới cho trạm ${deviceId}`);
    const success = await this.mqttService.publishConfig(deviceId, dto);
    return {
      status: success ? 'success' : 'failed',
      deviceId,
      config: dto,
    };
  }
}
