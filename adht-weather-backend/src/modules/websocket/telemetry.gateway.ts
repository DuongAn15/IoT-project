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

@WebSocketGateway({
  cors: { origin: '*' },
  path: '/ws/telemetry',
})
export class TelemetryGateway implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server: Server;

  private readonly logger = new Logger(TelemetryGateway.name);

  afterInit(server: Server) {
    this.logger.log('WebSocket Gateway đã sẵn sàng tại path: /ws/telemetry');
  }

  handleConnection(client: Socket) {
    this.logger.log(`[WS] Client kết nối: ${client.id}`);
  }

  handleDisconnect(client: Socket) {
    this.logger.log(`[WS] Client ngắt kết nối: ${client.id}`);
  }

  @SubscribeMessage('ping')
  handlePing(client: Socket): string {
    return 'pong';
  }

  broadcastTelemetry(data: any) {
    // TODO: Phát số đo tức thời tới tất cả client đang kết nối (Mobile App & Web Dashboard)
    if (this.server) {
      this.server.emit('telemetry', data);
    }
  }

  broadcastStatus(data: any) {
    // TODO: Phát trạng thái Online / Offline của trạm tới các client
    if (this.server) {
      this.server.emit('status', data);
    }
  }
}
