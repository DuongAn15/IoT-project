import { Injectable, Logger } from '@nestjs/common';
import { MqttService } from '../mqtt/mqtt.service';
import { SendCommandDto } from './dto/send-command.dto';
import { UpdateConfigDto } from './dto/update-config.dto';

@Injectable()
export class DevicesService {
  private readonly logger = new Logger(DevicesService.name);

  constructor(private readonly mqttService: MqttService) {}

  sendCommand(deviceId: string, dto: SendCommandDto) {
    this.logger.log(`[DevicesService] Nhận lệnh điều khiển cho trạm ${deviceId}: ${dto.cmd}`);
    // TODO: Phát lệnh xuống ESP32 qua MqttService
    const success = this.mqttService.publishCommand(deviceId, dto);
    return {
      status: success ? 'success' : 'failed',
      deviceId,
      command: dto,
    };
  }

  updateConfig(deviceId: string, dto: UpdateConfigDto) {
    this.logger.log(`[DevicesService] Nhận cấu hình mới cho trạm ${deviceId}`);
    // TODO: Phát cấu hình mới xuống ESP32 qua MqttService
    const success = this.mqttService.publishConfig(deviceId, dto);
    return {
      status: success ? 'success' : 'failed',
      deviceId,
      config: dto,
    };
  }
}
