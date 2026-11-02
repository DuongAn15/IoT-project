import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsNumber, IsOptional } from 'class-validator';

export class UpdateConfigDto {
  @ApiPropertyOptional({ example: 38.0, description: 'Ngưỡng nhiệt độ tối đa (°C)' })
  @IsNumber()
  @IsOptional()
  temp_max?: number;

  @ApiPropertyOptional({ example: 10.0, description: 'Ngưỡng nhiệt độ tối thiểu (°C)' })
  @IsNumber()
  @IsOptional()
  temp_min?: number;

  @ApiPropertyOptional({ example: 90.0, description: 'Ngưỡng độ ẩm tối đa (%)' })
  @IsNumber()
  @IsOptional()
  humi_max?: number;

  @ApiPropertyOptional({ example: 15.0, description: 'Ngưỡng tốc độ gió nguy hiểm (m/s)' })
  @IsNumber()
  @IsOptional()
  wind_max?: number;

  @ApiPropertyOptional({ example: 30.0, description: 'Ngưỡng mưa giông (mm/h)' })
  @IsNumber()
  @IsOptional()
  rain_max?: number;

  @ApiPropertyOptional({ example: true, description: 'Tự động báo còi khi vượt ngưỡng' })
  @IsBoolean()
  @IsOptional()
  auto_warning?: boolean;

  @ApiPropertyOptional({ example: true, description: 'Bật/Tắt còi Buzzer' })
  @IsBoolean()
  @IsOptional()
  buzzer?: boolean;
}

