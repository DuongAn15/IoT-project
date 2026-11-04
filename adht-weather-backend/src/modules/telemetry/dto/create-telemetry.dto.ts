import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';

export class CreateTelemetryDto {
  @ApiProperty({ example: 'adht_weather_01', description: 'Mã định danh duy nhất của trạm' })
  @IsString()
  @IsNotEmpty()
  device_id: string;

  @ApiPropertyOptional({ example: 1714567890, description: 'Unix timestamp' })
  @IsNumber()
  @IsOptional()
  timestamp?: number;

  @ApiProperty({ example: 31.4, description: 'Nhiệt độ môi trường (°C)' })
  @IsNumber()
  @Min(-40)
  @Max(80)
  temp: number;

  @ApiProperty({ example: 68.0, description: 'Độ ẩm tương đối (%)' })
  @IsNumber()
  @Min(0)
  @Max(100)
  humi: number;

  @ApiPropertyOptional({ example: 36.2, description: 'Chỉ số nhiệt cảm nhận (°C)' })
  @IsNumber()
  @IsOptional()
  heat_index?: number;

  @ApiProperty({ example: 0.0, description: 'Cường độ mưa tức thời (mm/h)' })
  @IsNumber()
  @Min(0)
  rain_rate: number;

  @ApiProperty({ example: 12.5, description: 'Lượng mưa tích lũy trong ngày (mm)' })
  @IsNumber()
  @Min(0)
  rain_daily: number;

  @ApiProperty({ example: 2.1, description: 'Tốc độ gió tức thời (m/s)' })
  @IsNumber()
  @Min(0)
  wind_speed: number;

  @ApiPropertyOptional({ example: 4.5, description: 'Tốc độ gió giật lớn nhất (m/s)' })
  @IsNumber()
  @IsOptional()
  wind_max?: number;

  @ApiPropertyOptional({ example: -58, description: 'Cường độ sóng WiFi (dBm)' })
  @IsNumber()
  @IsOptional()
  rssi?: number;

  @ApiPropertyOptional({ example: 3600, description: 'Thời gian hoạt động liên tục (giây)' })
  @IsNumber()
  @IsOptional()
  uptime?: number;
}
