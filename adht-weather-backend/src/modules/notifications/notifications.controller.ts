import { Controller, Post, Body } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { NotificationsService } from './notifications.service';
import { RegisterFcmTokenDto } from './dto/register-fcm-token.dto';

@ApiTags('Notifications')
@Controller('notifications')
export class NotificationsController {
  constructor(private readonly notificationsService: NotificationsService) {}

  @Post('register-token')
  @ApiOperation({ summary: 'Đăng ký thiết bị di động nhận thông báo đẩy qua FCM' })
  @ApiResponse({ status: 200, description: 'Đăng ký FCM Token thành công' })
  async registerToken(@Body() dto: RegisterFcmTokenDto) {
    return this.notificationsService.registerToken(dto.fcm_token);
  }
}

