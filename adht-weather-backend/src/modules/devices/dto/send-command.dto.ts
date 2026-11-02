import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsOptional, IsString } from 'class-validator';

export class SendCommandDto {
  @ApiProperty({ example: 'buzzer', description: 'Lệnh: buzzer, led, reboot, reset_rain' })
  @IsString()
  @IsNotEmpty()
  cmd: string;

  @ApiPropertyOptional({ example: '500', description: 'Tham số lệnh (ví dụ thời gian còi kêu ms)' })
  @IsString()
  @IsOptional()
  arg?: string;
}

