import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse, ApiBearerAuth } from '@nestjs/swagger';
import { WeatherService } from './weather.service';
import { QueryHistoryDto } from './dto/query-history.dto';
import { ApiAuthGuard } from '../../common/guards/api-auth.guard';

/* Forecast coordinate parser; keep disabled with the deferred route.
function parseCoordinate(value: unknown): number | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== 'string' || value.trim() === '') return NaN;
  return Number(value);
}
*/

@ApiTags('Weather')
@ApiBearerAuth()
@UseGuards(ApiAuthGuard)
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
    return this.weatherService.getHistory(query.device_id, query.range, query.since);
  }

  /* Forecast endpoint is deferred; re-enable only with an approved forecast scope.
  @Get('forecast')
  @ApiOperation({ summary: 'Dự báo thời tiết 3 ngày tới' })
  @ApiResponse({ status: 200, description: 'Thông tin dự báo thời tiết' })
  getForecast(@Query('lat') lat?: string, @Query('lon') lon?: string) {
    return this.weatherService.getForecast(
      parseCoordinate(lat),
      parseCoordinate(lon),
    );
  }
  */
}
