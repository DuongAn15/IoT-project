import { BadRequestException, ForbiddenException, Injectable, Logger, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { MqttService } from '../mqtt/mqtt.service';
import { ALLOWED_DEVICE_COMMANDS, SendCommandDto } from './dto/send-command.dto';
import { UpdateConfigDto } from './dto/update-config.dto';
import { CreateDeviceDto } from './dto/create-device.dto';
import { SupabaseService } from '../database/supabase.service';
import { DeviceOperationsService } from './device-operations.service';

const LED_ALLOWED_ARGS = new Set(['', '0', '1', 'on', 'off', 'true', 'false', 'auto']);

@Injectable()
export class DevicesService {
  private readonly logger = new Logger(DevicesService.name);
  private readonly ops: DeviceOperationsService;

  constructor(
    private readonly mqttService: MqttService,
    private readonly supabaseService: SupabaseService,
    @Optional() private readonly configService?: ConfigService,
    @Optional() operationsService?: DeviceOperationsService,
  ) {
    this.ops = operationsService ?? new DeviceOperationsService(configService);
    const maybeMqtt = this.mqttService as unknown as {
      setDeviceAckHandler?: (cb: (deviceId: string, payload: Record<string, unknown>) => void) => void;
    };
    maybeMqtt?.setDeviceAckHandler?.((deviceId, payload) => {
      this.ops.handleDeviceAck(deviceId, payload);
    });
  }

  private assertValidDeviceAccess(deviceId: string): string {
    const trimmed = typeof deviceId === 'string' ? deviceId.trim() : '';
    if (!trimmed || /[/+#\u0000\s]/.test(trimmed)) {
      throw new BadRequestException('Invalid device_id');
    }
    const allowedDevices = this.configService?.get<string[]>('auth.allowedDevices') || [];
    if (allowedDevices.length > 0 && !allowedDevices.includes(trimmed)) {
      throw new ForbiddenException(`Access to device ${trimmed} is not allowed`);
    }
    return trimmed;
  }

  private assertValidCommand(dto: SendCommandDto): void {
    if (!dto || typeof dto.cmd !== 'string' || !ALLOWED_DEVICE_COMMANDS.includes(dto.cmd as never)) {
      throw new BadRequestException(`cmd must be one of: ${ALLOWED_DEVICE_COMMANDS.join(', ')}`);
    }
    if (dto.arg === undefined) return;
    const arg = dto.arg.trim();
    if (dto.cmd === 'buzzer' && arg !== '') {
      if (!/^\d+$/.test(arg)) {
        throw new BadRequestException('buzzer arg must be an integer duration in ms (50..10000)');
      }
      const ms = Number(arg);
      if (ms < 50 || ms > 10000) {
        throw new BadRequestException('buzzer arg must be between 50 and 10000 ms');
      }
    } else if (dto.cmd === 'led' && !LED_ALLOWED_ARGS.has(arg.toLowerCase())) {
      throw new BadRequestException('led arg must be one of: on, off, true, false, 0, 1, auto');
    }
  }

  private assertValidConfig(dto: UpdateConfigDto): void {
    if (!dto || typeof dto !== 'object') {
      throw new BadRequestException('Configuration payload is required');
    }
    const keys: (keyof UpdateConfigDto)[] = [
      'temp_max',
      'temp_min',
      'humi_max',
      'wind_max',
      'rain_max',
      'auto_warning',
      'buzzer',
    ];
    const hasAnyField = keys.some((key) => dto[key] !== undefined);
    if (!hasAnyField) {
      throw new BadRequestException('At least one configuration field is required');
    }
    if (dto.temp_min !== undefined && dto.temp_max !== undefined && dto.temp_min >= dto.temp_max) {
      throw new BadRequestException('temp_min must be strictly less than temp_max');
    }
  }

  createDevice(dto: CreateDeviceDto) {
    return this.supabaseService.createDevice(dto);
  }

  async getDevices() {
    const devices = await this.supabaseService.getDevices();
    const allowedDevices = this.configService?.get<string[]>('auth.allowedDevices') || [];
    if (allowedDevices.length === 0) {
      return devices;
    }
    return devices.filter((device) => allowedDevices.includes(device.device_id));
  }

  getDevice(deviceId: string) {
    const id = this.assertValidDeviceAccess(deviceId);
    return this.supabaseService.getDevice(id);
  }

  getStationState(deviceId: string) {
    const id = this.assertValidDeviceAccess(deviceId);
    return this.ops.getStationState(id);
  }

  getOperation(deviceId: string, operationId: string) {
    const id = this.assertValidDeviceAccess(deviceId);
    return this.ops.getOperation(id, operationId);
  }

  async sendCommand(deviceId: string, dto: SendCommandDto) {
    const id = this.assertValidDeviceAccess(deviceId);
    this.assertValidCommand(dto);
    const { operation, duplicate } = this.ops.createCommandOperation(id, dto);
    if (duplicate) {
      return {
        status: operation.status === 'failed' ? 'failed' : operation.status,
        delivery: operation.broker_acked_at ? 'broker_ack' : 'failed',
        executed: operation.status === 'applied',
        duplicate: true,
        operation_id: operation.operation_id,
        operation_status: operation.status,
        expires_at: operation.expires_at,
        deviceId: id,
        command: dto,
      };
    }

    this.logger.log(`[DevicesService] Nhận lệnh điều khiển cho trạm ${id}: ${dto.cmd}`);
    const success = await this.mqttService.publishCommand(id, {
      schema_version: 2,
      request_id: operation.operation_id,
      expires_at: operation.expires_at,
      ...(operation.deployment_id ? { deployment_id: operation.deployment_id } : {}),
      cmd: dto.cmd,
      ...(dto.arg !== undefined ? { arg: dto.arg } : {}),
    });
    const updated = this.ops.markPublishResult(id, operation.operation_id, success) ?? operation;
    return {
      status: success ? 'published' : 'failed',
      delivery: success ? 'broker_ack' : 'failed',
      executed: false,
      operation_id: updated.operation_id,
      operation_status: updated.status,
      expires_at: updated.expires_at,
      deviceId: id,
      command: dto,
    };
  }

  async updateConfig(deviceId: string, dto: UpdateConfigDto) {
    const id = this.assertValidDeviceAccess(deviceId);
    this.assertValidConfig(dto);
    const { operation, duplicate, mergedConfig } = this.ops.createConfigOperation(id, dto);
    if (duplicate) {
      return {
        status: operation.status === 'failed' ? 'failed' : operation.status,
        delivery: operation.broker_acked_at ? 'broker_ack' : 'failed',
        executed: operation.status === 'persisted' || operation.status === 'applied',
        duplicate: true,
        operation_id: operation.operation_id,
        operation_status: operation.status,
        desired_version: operation.desired_version,
        expires_at: operation.expires_at,
        deviceId: id,
        config: mergedConfig,
      };
    }

    this.logger.log(`[DevicesService] Nhận cấu hình mới cho trạm ${id} (v${operation.desired_version})`);
    const success = await this.mqttService.publishConfig(id, {
      schema_version: 2,
      request_id: operation.operation_id,
      version: operation.desired_version,
      expires_at: operation.expires_at,
      ...(operation.deployment_id ? { deployment_id: operation.deployment_id } : {}),
      ...mergedConfig,
    });
    const updated = this.ops.markPublishResult(id, operation.operation_id, success) ?? operation;
    return {
      status: success ? 'published' : 'failed',
      delivery: success ? 'broker_ack' : 'failed',
      executed: false,
      operation_id: updated.operation_id,
      operation_status: updated.status,
      desired_version: updated.desired_version,
      expires_at: updated.expires_at,
      deviceId: id,
      config: mergedConfig,
    };
  }
}
