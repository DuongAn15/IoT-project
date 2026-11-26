import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsNotEmpty, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class RegisterFcmTokenDto {
  @ApiProperty({ description: 'Firebase Cloud Messaging Device Registration Token' })
  @IsString()
  @IsNotEmpty()
  @MinLength(10)
  @MaxLength(4096)
  fcm_token: string;

  @ApiPropertyOptional({ description: 'Tên thiết bị (ví dụ: iPhone 15 Pro, Samsung Galaxy S24)' })
  @IsString()
  @MaxLength(128)
  @IsOptional()
  device_name?: string;
}
