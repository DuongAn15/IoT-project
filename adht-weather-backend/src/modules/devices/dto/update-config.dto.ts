import { ApiPropertyOptional } from '@nestjs/swagger';
import { IsBoolean, IsNumber, IsOptional, Max, Min } from 'class-validator';

export class UpdateConfigDto {
  @ApiPropertyOptional({ example: 38.0, description: 'Ngưỡng nhiệt độ tối đa (°C)' })
  @IsNumber()
  @Min(-40)
  @Max(80)
  @IsOptional()
  temp_max?: number;

  @ApiPropertyOptional({ example: 10.0, description: 'Ngưỡng nhiệt độ tối thiểu (°C)' })
  @IsNumber()
  @Min(-40)
  @Max(80)
  @IsOptional()
  temp_min?: number;

  @ApiPropertyOptional({ example: 90.0, description: 'Ngưỡng độ ẩm tối đa (%)' })
  @IsNumber()
  @Min(0)
  @Max(100)
  @IsOptional()
  humi_max?: number;

  @ApiPropertyOptional({ example: 15.0, description: 'Ngưỡng tốc độ gió nguy hiểm (m/s)' })
  @IsNumber()
  @Min(0)
  @Max(100)
  @IsOptional()
  wind_max?: number;

  @ApiPropertyOptional({ example: 30.0, description: 'Ngưỡng mưa giông (mm/h)' })
  @IsNumber()
  @Min(0)
  @Max(500)
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
