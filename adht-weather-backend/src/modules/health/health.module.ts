import { Module } from '@nestjs/common';
import { HealthController } from './health.controller';

// MqttService đến từ MqttModule (@Global) nên không cần import thêm.
@Module({
  controllers: [HealthController],
})
export class HealthModule {}
