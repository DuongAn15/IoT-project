import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsISO8601, IsOptional, IsString } from 'class-validator';

export class QueryHistoryDto {
  @ApiPropertyOptional({ example: 'adht_weather_01', description: 'Mã trạm' })
  @IsString()
  @IsOptional()
  device_id?: string = 'adht_weather_01';

  @ApiPropertyOptional({ example: '24h', description: 'Khung thời gian (1h, 6h, 24h, 3d, 7d)' })
  @IsIn(['1h', '6h', '24h', '3d', '7d'])
  @IsOptional()
  range?: string = '24h';

  @ApiPropertyOptional({ example: '2026-11-27T00:00:00.000Z', description: 'Mốc UTC incremental sync (>= since)' })
  @IsISO8601()
  @IsOptional()
  since?: string;
}
