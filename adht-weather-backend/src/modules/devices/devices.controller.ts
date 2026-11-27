import { Controller, Get, Post, Put, Param, Body, UseGuards, HttpCode, HttpStatus } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { DevicesService } from './devices.service';
import { SendCommandDto } from './dto/send-command.dto';
import { UpdateConfigDto } from './dto/update-config.dto';
import { CreateDeviceDto } from './dto/create-device.dto';
import { ApiAuthGuard } from '../../common/guards/api-auth.guard';

@ApiTags('Devices')
@ApiBearerAuth()
@UseGuards(ApiAuthGuard)
@Controller('devices')
export class DevicesController {
  constructor(private readonly devicesService: DevicesService) {}

  @Post()
  @ApiOperation({ summary: 'Thêm thiết bị vào Supabase' })
  @ApiResponse({ status: 201, description: 'Đã tạo thiết bị' })
  @ApiResponse({ status: 400, description: 'Dữ liệu không hợp lệ' })
  @ApiResponse({ status: 409, description: 'Device ID hoặc MAC đã tồn tại' })
  createDevice(@Body() dto: CreateDeviceDto) {
    return this.devicesService.createDevice(dto);
  }

  @Get()
  @ApiOperation({ summary: 'Lấy tất cả thiết bị' })
  getDevices() {
    return this.devicesService.getDevices();
  }

  @Get(':id')
  @ApiOperation({ summary: 'Lấy thiết bị theo device_id' })
  @ApiResponse({ status: 404, description: 'Không tìm thấy thiết bị' })
  getDevice(@Param('id') deviceId: string) {
    return this.devicesService.getDevice(deviceId);
  }

  @Get(':id/state')
  @ApiOperation({ summary: 'Lấy desired/reported config, version và các operation gần nhất của trạm' })
  getStationState(@Param('id') deviceId: string) {
    return this.devicesService.getStationState(deviceId);
  }

  @Get(':id/operations/:operationId')
  @ApiOperation({ summary: 'Truy vấn trạng thái một operation config/command để reconcile' })
  getOperation(
    @Param('id') deviceId: string,
    @Param('operationId') operationId: string,
  ) {
    return this.devicesService.getOperation(deviceId, operationId);
  }

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
