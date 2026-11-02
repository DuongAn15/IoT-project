import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsOptional, IsString } from 'class-validator';

export class RegisterFcmTokenDto {
  @ApiProperty({ description: 'Firebase Cloud Messaging Device Registration Token' })
  @IsString()
  @IsNotEmpty()
  fcm_token: string;

  @ApiPropertyOptional({ description: 'Tên thiết bị (ví dụ: iPhone 15 Pro, Samsung Galaxy S24)' })
  @IsString()
  @IsOptional()
  device_name?: string;
}

