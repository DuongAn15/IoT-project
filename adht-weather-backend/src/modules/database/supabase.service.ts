import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export interface WeatherRecord {
  device_id: string;
  temp: number;
  humi: number;
  heat_index?: number;
  rain_rate: number;
  rain_daily: number;
  wind_speed: number;
  wind_max?: number;
  rssi?: number;
  uptime?: number;
  recorded_at: string;
}

@Injectable()
export class SupabaseService {
  private readonly logger = new Logger(SupabaseService.name);

  constructor(private readonly config: ConfigService) {
    // TODO: Khởi tạo kết nối Supabase Client (@supabase/supabase-js) hoặc TypeORM / Prisma
    this.logger.log('SupabaseService stub initialized');
  }

  async saveTelemetry(data: Partial<WeatherRecord>): Promise<boolean> {
    // TODO: Bạn viết code lưu bản ghi số đo cảm biến vào bảng weather_logs ở đây
    this.logger.log(`[TODO] Lưu telemetry vào CSDL cho trạm: ${data?.device_id}`);
    return true;
  }

  getLatest(deviceId?: string): WeatherRecord | null {
    // TODO: Bạn viết code truy vấn bản ghi mới nhất của trạm ở đây
    this.logger.log(`[TODO] Lấy số đo mới nhất của trạm: ${deviceId || 'mặc định'}`);
    return null;
  }

  async getHistory(deviceId: string, range: string = '24h'): Promise<any[]> {
    // TODO: Bạn viết code truy vấn chuỗi thời gian và thuật toán Downsampling ở đây
    this.logger.log(`[TODO] Lấy lịch sử và làm mịn dữ liệu cho trạm: ${deviceId}, khung: ${range}`);
    return [];
  }
}
