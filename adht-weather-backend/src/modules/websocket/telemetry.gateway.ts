import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayInit,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
} from '@nestjs/websockets';
import { Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import type { CreateTelemetryDto } from '../telemetry/dto/create-telemetry.dto';

@WebSocketGateway({
  cors: { origin: '*' },
  path: '/ws/telemetry',
})
export class TelemetryGateway implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server?: Server;

  private readonly logger = new Logger(TelemetryGateway.name);

  afterInit(server: Server): void {
    this.server = server;
    this.logger.log('WebSocket Gateway đã sẵn sàng tại path: /ws/telemetry');
  }

  handleConnection(client: Socket): void {
    this.logger.log(`[WS] Client kết nối: ${client.id}`);
  }

  handleDisconnect(client: Socket): void {
    this.logger.log(`[WS] Client ngắt kết nối: ${client.id}`);
  }

  @SubscribeMessage('ping')
  handlePing(client: Socket): string {
    return 'pong';
  }

  broadcastTelemetry(data: CreateTelemetryDto): void {
    this.server?.emit('telemetry', data);
  }

  broadcastStatus(data: object): void {
    this.server?.emit('status', data);
  }
}