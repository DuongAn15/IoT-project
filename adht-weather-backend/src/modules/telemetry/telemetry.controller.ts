import { Controller, Post, Body, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { TelemetryService } from './telemetry.service';
import { CreateTelemetryDto } from './dto/create-telemetry.dto';
import { ApiAuthGuard } from '../../common/guards/api-auth.guard';

@ApiTags('Telemetry')
@ApiBearerAuth()
@UseGuards(ApiAuthGuard)
@Controller('telemetry')
export class TelemetryController {
  constructor(private readonly telemetryService: TelemetryService) {}

  @Post()
  @ApiOperation({ summary: 'Tiếp nhận Webhook dữ liệu cảm biến từ EMQX Cloud Rule Engine' })
  @ApiResponse({ status: 200, description: 'Xử lý telemetry thành công' })
  async ingestTelemetry(@Body() dto: CreateTelemetryDto) {
    return this.telemetryService.processWebhook(dto);
  }
}

