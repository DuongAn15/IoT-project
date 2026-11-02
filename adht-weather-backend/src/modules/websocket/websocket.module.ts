import { Global, Module } from '@nestjs/common';
import { TelemetryGateway } from './telemetry.gateway';

@Global()
@Module({
  providers: [TelemetryGateway],
  exports: [TelemetryGateway],
})
export class WebsocketModule {}

