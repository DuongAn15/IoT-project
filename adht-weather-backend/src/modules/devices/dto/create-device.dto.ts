import { Transform } from 'class-transformer';
import { IsNotEmpty, IsString, Matches } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class CreateDeviceDto {
  @ApiProperty({ example: 'adht_weather_02' })
  @Transform(({ value }) => typeof value === 'string' ? value.trim() : value)
  @IsString()
  @IsNotEmpty()
  device_id: string;

  @ApiProperty({ example: 'Trạm 02 Ảo - Nắng Nóng' })
  @Transform(({ value }) => typeof value === 'string' ? value.trim() : value)
  @IsString()
  @IsNotEmpty()
  name: string;

  @ApiProperty({ example: '02:00:00:00:00:02' })
  @Transform(({ value }) => typeof value === 'string' ? value.trim().toUpperCase() : value)
  @IsString()
  @Matches(/^([0-9A-F]{2}:){5}[0-9A-F]{2}$/, {
    message: 'mac must contain six hexadecimal pairs separated by colons',
  })
  mac: string;
}
