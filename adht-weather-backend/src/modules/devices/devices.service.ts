import { BadRequestException, ForbiddenException, Injectable, Logger, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { MqttService } from '../mqtt/mqtt.service';
import { ALLOWED_DEVICE_COMMANDS, SendCommandDto } from './dto/send-command.dto';
import { UpdateConfigDto } from './dto/update-config.dto';
import { CreateDeviceDto } from './dto/create-device.dto';
import { SupabaseService } from '../database/supabase.service';

const LED_ALLOWED_ARGS = new Set(['', '0', '1', 'on', 'off', 'true', 'false', 'auto']);

@Injectable()
export class DevicesService {
  private readonly logger = new Logger(DevicesService.name);

  constructor(
    private readonly mqttService: MqttService,
    private readonly supabaseService: SupabaseService,
    @Optional() private readonly configService?: ConfigService,
  ) {}

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

  private resolveStationLocation(deviceId: string): string | undefined {
    const raw = this.configService?.get<string>('STATION_LOCATIONS') ?? process.env.STATION_LOCATIONS;
    if (raw) {
      try {
        const map = JSON.parse(raw) as Record<string, unknown>;
        const value = map[deviceId];
        if (typeof value === 'string' && value.trim()) return value.trim();
      } catch {
        // Location labels may contain commas; only JSON mappings are accepted.
      }
    }
    const fallback: Record<string, string> = {
      adht_weather_01: 'Trung tâm, Đà Nẵng, Việt Nam',
      adht_weather_02: 'Bán đảo Sơn Trà, Đà Nẵng, Việt Nam',
      adht_weather_03: 'Hòa Vang, Đà Nẵng, Việt Nam',
    };
    return fallback[deviceId];
  }

  async getDevices() {
    const devices = await this.supabaseService.getDevices();
    const allowedDevices = this.configService?.get<string[]>('auth.allowedDevices') || [];
    const filtered = allowedDevices.length === 0
      ? devices
      : devices.filter((device) => allowedDevices.includes(device.device_id));
    return filtered.map((device) => ({
      ...device,
      location: this.resolveStationLocation(device.device_id),
    }));
  }

  async getDevice(deviceId: string) {
    const id = this.assertValidDeviceAccess(deviceId);
    const device = await this.supabaseService.getDevice(id);
    return {
      ...device,
      location: this.resolveStationLocation(device.device_id),
    };
  }

  async sendCommand(deviceId: string, dto: SendCommandDto) {
    const id = this.assertValidDeviceAccess(deviceId);
    this.assertValidCommand(dto);
    this.logger.log(`[DevicesService] Nhận lệnh điều khiển cho trạm ${id}: ${dto.cmd}`);
    const success = await this.mqttService.publishCommand(id, dto);
    return {
      status: success ? 'accepted' : 'failed',
      delivery: success ? 'broker_ack' : 'failed',
      executed: false,
      deviceId: id,
      command: dto,
    };
  }

  async updateConfig(deviceId: string, dto: UpdateConfigDto) {
    const id = this.assertValidDeviceAccess(deviceId);
    this.assertValidConfig(dto);
    this.logger.log(`[DevicesService] Nhận cấu hình mới cho trạm ${id}`);
    const success = await this.mqttService.publishConfig(id, dto);
    return {
      status: success ? 'accepted' : 'failed',
      delivery: success ? 'broker_ack' : 'failed',
      executed: false,
      deviceId: id,
      config: dto,
    };
  }
}
