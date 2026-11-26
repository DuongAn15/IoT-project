import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayInit,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
} from '@nestjs/websockets';
import { Logger, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Server, Socket } from 'socket.io';
import type { CreateTelemetryDto } from '../telemetry/dto/create-telemetry.dto';
import { extractBearerOrApiKey, safeTokenMatch } from '../../common/guards/api-auth.guard';

@WebSocketGateway({
  cors: {
    origin: process.env.CORS_ORIGINS
      ? process.env.CORS_ORIGINS.split(',').map((o) => o.trim()).filter((o) => o && o !== '*')
      : process.env.NODE_ENV === 'production'
        ? false
        : true,
    credentials: Boolean(process.env.CORS_ORIGINS),
  },
  path: '/ws/telemetry',
})
export class TelemetryGateway implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect {
  @WebSocketServer()
  server?: Server;

  private readonly logger = new Logger(TelemetryGateway.name);

  constructor(@Optional() private readonly configService?: ConfigService) {}

  afterInit(server: Server): void {
    this.server = server;
    this.logger.log('WebSocket Gateway đã sẵn sàng tại path: /ws/telemetry');
  }

  handleConnection(client: Socket): void {
    const expectedToken =
      this.configService?.get<string>('auth.apiToken') || process.env.API_AUTH_TOKEN?.trim();
    const nodeEnv =
      this.configService?.get<string>('nodeEnv') || process.env.NODE_ENV || 'development';

    if (expectedToken || nodeEnv === 'production') {
      const authToken =
        typeof client.handshake.auth?.token === 'string'
          ? client.handshake.auth.token.trim()
          : undefined;
      const headerToken = extractBearerOrApiKey(
        client.handshake.headers as Record<string, string | string[] | undefined>,
      );
      if (!safeTokenMatch(authToken || headerToken, expectedToken)) {
        this.logger.warn(`[WS] Rejected unauthorized client: ${client.id}`);
        client.disconnect(true);
        return;
      }
    }

    this.logger.log(`[WS] Client kết nối: ${client.id}`);
  }

  handleDisconnect(client: Socket): void {
    this.logger.log(`[WS] Client ngắt kết nối: ${client.id}`);
  }

  @SubscribeMessage('ping')
  handlePing(_client: Socket): string {
    return 'pong';
  }

  @SubscribeMessage('subscribe_station')
  handleSubscribeStation(client: Socket, deviceId: unknown): { subscribed: string } | { error: string } {
    if (typeof deviceId !== 'string' || !deviceId.trim()) {
      return { error: 'device_id is required' };
    }
    const target = `station:${deviceId.trim()}`;
    for (const room of client.rooms) {
      if (room.startsWith('station:') && room !== target) {
        void client.leave(room);
      }
    }
    void client.join(target);
    return { subscribed: deviceId.trim() };
  }

  broadcastTelemetry(data: CreateTelemetryDto): void {
    if (!this.server) return;
    const deviceId = typeof data?.device_id === 'string' ? data.device_id.trim() : '';
    const stationRoom = deviceId ? `station:${deviceId}` : '';

    // Send to station-subscribed sockets and unscoped sockets, avoiding cross-station leaks.
    const sockets = this.server.sockets?.sockets;
    if (!sockets || sockets.size === 0) {
      this.server.emit('telemetry', data);
      return;
    }

    for (const socket of sockets.values()) {
      const stationRooms = [...socket.rooms].filter((room) => room.startsWith('station:'));
      if (stationRooms.length === 0 || (stationRoom && stationRooms.includes(stationRoom))) {
        socket.emit('telemetry', data);
      }
    }
  }

  broadcastStatus(data: object): void {
    this.server?.emit('status', data);
  }
}
