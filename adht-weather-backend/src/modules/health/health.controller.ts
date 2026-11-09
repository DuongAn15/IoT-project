import { Controller, Get } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { MqttService } from '../mqtt/mqtt.service';

/**
 * Endpoint nhẹ cho Render health check và UptimeRobot ping (giữ instance free không ngủ).
 * Không gọi Supabase/Firebase để mỗi lần ping không tốn tài nguyên bên ngoài.
 * Luôn trả 200 kể cả khi MQTT đang mất kết nối: MQTT tự reconnect, nếu trả lỗi
 * thì Render sẽ restart service liên tục. Trạng thái MQTT chỉ để quan sát.
 */
@ApiTags('Health')
@Controller('health')
export class HealthController {
  constructor(private readonly mqttService: MqttService) {}

  @Get()
  @ApiOperation({ summary: 'Kiểm tra backend còn sống (health check / uptime ping)' })
  @ApiResponse({ status: 200, description: 'Backend đang chạy; kèm trạng thái kết nối MQTT' })
  check() {
    return {
      status: 'ok',
      mqtt_connected: this.mqttService.isConnected,
      uptime_sec: Math.round(process.uptime()),
    };
  }
}
