import { BadRequestException, ForbiddenException, Injectable, Optional } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SupabaseService } from '../database/supabase.service';

/* Forecast-only dependencies; restore with the deferred getForecast implementation.
import { BadGatewayException, Logger, ServiceUnavailableException } from '@nestjs/common';
import axios from 'axios';
import type { WeatherForecast } from './types/forecast.types';
import { buildForecast } from './utils/forecast.helpers';

const OPENWEATHER_FORECAST_URL = 'https://api.openweathermap.org/data/2.5/forecast';
*/

@Injectable()
export class WeatherService {
    constructor(
        private readonly supabaseService: SupabaseService,
        @Optional() private readonly configService?: ConfigService,
    ) { }

    private assertAllowedDevice(deviceId?: string): string | undefined {
        if (deviceId === undefined) return undefined;
        const trimmed = deviceId.trim();
        if (!trimmed || /[/+#\u0000\s]/.test(trimmed)) {
            throw new BadRequestException('Invalid device_id');
        }
        const allowedDevices = this.configService?.get<string[]>('auth.allowedDevices') || [];
        if (allowedDevices.length > 0 && !allowedDevices.includes(trimmed)) {
            throw new ForbiddenException(`Access to device ${trimmed} is not allowed`);
        }
        return trimmed;
    }

    async getLatest(deviceId?: string) {
        const resolvedId = this.assertAllowedDevice(deviceId);
        return this.supabaseService.getLatest(resolvedId);
    }

    async getHistory(deviceId: string, range: string = '24h', since?: string) {
        const resolvedId = this.assertAllowedDevice(deviceId) || '';
        const data = await this.supabaseService.getHistory(resolvedId, range, since);
        return {
            device_id: resolvedId,
            range,
            points_count: data.length,
            data,
        };
    }

    /* Forecast integration is deferred. Keep this code for a future scoped reactivation.
    async getForecast(lat?: number, lon?: number): Promise<WeatherForecast> {
        // const latitude = lat ?? this.config.getOrThrow<number>('openWeather.defaultLat');
        // const longitude = lon ?? this.config.getOrThrow<number>('openWeather.defaultLon');
        // if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
        //   !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
        //   throw new BadRequestException('lat must be between -90 and 90; lon must be between -180 and 180');
        // }
        // const apiKey = this.config.get<string>('openWeather.apiKey')?.trim();
        // if (!apiKey) throw new ServiceUnavailableException('OpenWeather API key is not configured');

        // let forecast: ReturnType<typeof buildForecast>;
        // try {
        //   const response = await axios.get<unknown>(OPENWEATHER_FORECAST_URL, {
        //     params: { lat: latitude, lon: longitude, appid: apiKey, units: 'metric', lang: 'vi' },
        //     timeout: 10000,
        //     maxRedirects: 0,
        //   });
        //   forecast = buildForecast(response.data, Date.now());
        // } catch (error: unknown) {
        //   // Axios errors can include the API key in request config; never log the raw error.
        //   if (axios.isAxiosError(error)) {
        //     const status = error.response?.status;
        //     if (status === 401 || status === 403) {
        //       this.logger.error('OpenWeather rejected the API key or API access');
        //       throw new ServiceUnavailableException('OpenWeather API credentials or subscription are not valid');
        //     }
        //     if (status === 429) {
        //       this.logger.warn('OpenWeather request quota exceeded');
        //       throw new ServiceUnavailableException('Forecast provider rate limit exceeded; try again later');
        //     }
        //   }
        //   this.logger.error('Unable to fetch or parse OpenWeather forecast');
        //   throw new BadGatewayException('Unable to load weather forecast');
        // }
        this.logger.log(`[TODO] Lấy dự báo thời tiết cho tọa độ: ${lat}, ${lon}`);

        return {
            status: 'success',
            coords: { lat, lon },
            forecast_days: [],
            timezone_offset_seconds: 0,
        };
    }
    */
}
