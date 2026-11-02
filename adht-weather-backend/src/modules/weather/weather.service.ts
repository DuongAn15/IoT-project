import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../database/supabase.service';

@Injectable()
export class WeatherService {
  private readonly logger = new Logger(WeatherService.name);

  constructor(
    private readonly config: ConfigService,
    private readonly supabaseService: SupabaseService,
  ) {}

  async getLatest(deviceId?: string) {
    // TODO: Viết code lấy số đo mới nhất từ SupabaseService
    return this.supabaseService.getLatest(deviceId);
  }

  async getHistory(deviceId: string, range: string = '24h') {
    // TODO: Viết code lấy dữ liệu lịch sử đã downsample từ SupabaseService
    const data = await this.supabaseService.getHistory(deviceId, range);
    return {
      device_id: deviceId,
      range,
      points_count: data.length,
      data,
    };
  }

  async getForecast(lat?: number, lon?: number) {
    // TODO: Viết code gọi OpenWeatherMap API để lấy dự báo thời tiết 3 ngày
    this.logger.log(`[TODO] Lấy dự báo thời tiết cho tọa độ: ${lat}, ${lon}`);
    return {
      status: 'success',
      message: 'TODO: Tích hợp OpenWeatherMap API',
      coords: { lat, lon },
      forecast_days: [],
    };
  }
}
