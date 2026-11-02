import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import configuration from './config/configuration';

import { DatabaseModule } from './modules/database/database.module';
import { WebsocketModule } from './modules/websocket/websocket.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { MqttModule } from './modules/mqtt/mqtt.module';
import { TelemetryModule } from './modules/telemetry/telemetry.module';
import { WeatherModule } from './modules/weather/weather.module';
import { DevicesModule } from './modules/devices/devices.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [configuration],
      envFilePath: ['.env', '../adht-weather-firmware/.env'],
    }),
    DatabaseModule,
    WebsocketModule,
    NotificationsModule,
    MqttModule,
    TelemetryModule,
    WeatherModule,
    DevicesModule,
  ],
})
export class AppModule {}

