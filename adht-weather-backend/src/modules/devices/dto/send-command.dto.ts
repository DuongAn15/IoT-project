import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsIn, IsNotEmpty, IsOptional, IsString, MaxLength } from 'class-validator';

export const ALLOWED_DEVICE_COMMANDS = ['buzzer', 'led', 'reset', 'reboot', 'reset_rain'] as const;
export type AllowedDeviceCommand = (typeof ALLOWED_DEVICE_COMMANDS)[number];

export class SendCommandDto {
  @ApiProperty({
    example: 'buzzer',
    enum: ALLOWED_DEVICE_COMMANDS,
    description: 'Lệnh: buzzer, led, reset, reboot, reset_rain',
  })
  @IsString()
  @IsNotEmpty()
  @IsIn(ALLOWED_DEVICE_COMMANDS)
  cmd: string;

  @ApiPropertyOptional({ example: '500', description: 'Tham số lệnh (ví dụ thời gian còi kêu ms)' })
  @IsString()
  @MaxLength(32)
  @IsOptional()
  arg?: string;
}
