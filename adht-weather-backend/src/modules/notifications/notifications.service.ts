import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(private readonly config: ConfigService) {
    // TODO: Khởi tạo Firebase Admin SDK từ serviceAccountKey.json
  }

  async checkAndAlert(telemetry: any): Promise<void> {
    // TODO: Viết code kiểm tra ngưỡng gió bão (wind_speed), mưa lớn (rain_rate), nắng nóng (temp)
    // Nếu vượt ngưỡng nguy hiểm -> gọi sendPushNotification()
    this.logger.log(`[TODO] Kiểm tra ngưỡng cảnh báo thiên tai cho trạm: ${telemetry?.device_id}`);
  }

  async sendPushNotification(title: string, body: string, data?: any): Promise<void> {
    // TODO: Viết code gọi Firebase Admin FCM gửi push notification tới Topic 'adht_weather_alerts'
    this.logger.log(`[TODO] Bắn FCM Alert: ${title} - ${body}`);
  }

  async registerToken(token: string, deviceName?: string): Promise<any> {
    // TODO: Viết code đăng ký FCM token vào Topic chung của Mobile App
    this.logger.log(`[TODO] Đăng ký FCM token: ${token.substring(0, 15)}...`);
    return {
      status: 'success',
      message: 'FCM Token registered (Stub)',
      token: token.substring(0, 15) + '...',
    };
  }
}
