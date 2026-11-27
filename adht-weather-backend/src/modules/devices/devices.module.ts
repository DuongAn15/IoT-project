import { Module } from '@nestjs/common';
import { DevicesController } from './devices.controller';
import { DevicesService } from './devices.service';
import { DeviceOperationsService } from './device-operations.service';

@Module({
  controllers: [DevicesController],
  providers: [DevicesService, DeviceOperationsService],
  exports: [DevicesService, DeviceOperationsService],
})
export class DevicesModule {}

