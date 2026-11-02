import { Controller, Post, Put, Param, Body } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { DevicesService } from './devices.service';
import { SendCommandDto } from './dto/send-command.dto';
import { UpdateConfigDto } from './dto/update-config.dto';

@ApiTags('Devices')
@Controller('devices')
export class DevicesController {
  constructor(private readonly devicesService: DevicesService) {}

  @Post(':id/command')
  @ApiOperation({ summary: 'Gửi lệnh điều khiển còi/LED xuống ESP32' })
  @ApiResponse({ status: 200, description: 'Lệnh đã được phát qua MQTT' })
  sendCommand(@Param('id') deviceId: string, @Body() dto: SendCommandDto) {
    return this.devicesService.sendCommand(deviceId, dto);
  }

  @Put(':id/config')
  @ApiOperation({ summary: 'Cập nhật cấu hình ngưỡng cảnh báo vào NVS Flash của ESP32' })
  @ApiResponse({ status: 200, description: 'Cấu hình đã được phát qua MQTT' })
  updateConfig(@Param('id') deviceId: string, @Body() dto: UpdateConfigDto) {
    return this.devicesService.updateConfig(deviceId, dto);
  }
}

