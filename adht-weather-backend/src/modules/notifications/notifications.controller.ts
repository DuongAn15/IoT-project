import { Controller, Post, Body, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { NotificationsService } from './notifications.service';
import { RegisterFcmTokenDto } from './dto/register-fcm-token.dto';
import { ApiAuthGuard } from '../../common/guards/api-auth.guard';

@ApiTags('Notifications')
@ApiBearerAuth()
@UseGuards(ApiAuthGuard)
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

