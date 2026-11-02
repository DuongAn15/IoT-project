import { Controller, Get, Query } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { WeatherService } from './weather.service';
import { QueryHistoryDto } from './dto/query-history.dto';

@ApiTags('Weather')
@Controller('weather')
export class WeatherController {
  constructor(private readonly weatherService: WeatherService) {}

  @Get('latest')
  @ApiOperation({ summary: 'Lấy số đo thời gian thực mới nhất của một trạm' })
  @ApiResponse({ status: 200, description: 'Bản ghi telemetry mới nhất' })
  getLatest(@Query('device_id') deviceId?: string) {
    return this.weatherService.getLatest(deviceId);
  }

  @Get('history')
  @ApiOperation({ summary: 'Truy vấn dữ liệu lịch sử đã được làm mịn (Downsampled)' })
  @ApiResponse({ status: 200, description: 'Danh sách điểm dữ liệu vẽ biểu đồ fl_chart' })
  getHistory(@Query() query: QueryHistoryDto) {
    return this.weatherService.getHistory(query.device_id, query.range);
  }

  @Get('forecast')
  @ApiOperation({ summary: 'Dự báo thời tiết 3 ngày tới' })
  @ApiResponse({ status: 200, description: 'Thông tin dự báo thời tiết' })
  getForecast(@Query('lat') lat?: number, @Query('lon') lon?: number) {
    return this.weatherService.getForecast(lat ? Number(lat) : undefined, lon ? Number(lon) : undefined);
  }
}

