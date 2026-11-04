import { BadRequestException, Injectable, Logger, OnModuleDestroy, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { App, cert, deleteApp, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging, Messaging } from 'firebase-admin/messaging';
import type { AppConfig } from '../../config/configuration.interface';
import type { CreateTelemetryDto } from '../telemetry/dto/create-telemetry.dto';

type AlertTelemetry = Pick<CreateTelemetryDto, 'device_id' | 'temp' | 'humi' | 'wind_speed' | 'rain_rate'>;
interface Alert {
  type: 'HIGH_TEMP' | 'LOW_TEMP' | 'HIGH_HUMIDITY' | 'STRONG_WIND' | 'HEAVY_RAIN';
  value: number;
  threshold: number;
  unit: string;
  title: string;
}
const FIREBASE_APP_NAME = 'adht-weather-notifications';
const ALERT_COOLDOWN_MS = 5 * 60 * 1000;

@Injectable()
export class NotificationsService implements OnModuleDestroy {
  private readonly logger = new Logger(NotificationsService.name);
  private readonly app: App;
  private readonly ownsApp: boolean;
  private readonly messaging: Messaging;
  private readonly topic: string;
  private readonly thresholds: AppConfig['thresholds'];
  private readonly alerts = new Map<string, { inFlight: boolean; sentAt?: number }>();

  constructor(private readonly config: ConfigService) {
    this.topic = this.config.getOrThrow<string>('firebase.alertTopic');
    this.thresholds = this.config.getOrThrow<AppConfig['thresholds']>('thresholds');
    if (!/^[a-zA-Z0-9\-_.~%]{1,900}$/.test(this.topic)) {
      throw new Error('Invalid FIREBASE_ALERT_TOPIC; use a topic name without /topics/');
    }
    if (Object.values(this.thresholds).some(value => !Number.isFinite(value))) {
      throw new Error('Invalid notification thresholds');
    }
    const existingApp = getApps().find(app => app.name === FIREBASE_APP_NAME);
    this.ownsApp = !existingApp;
    try {
      this.app = existingApp || initializeApp({
        credential: cert(this.config.getOrThrow<string>('firebase.credentialsPath')),
      }, FIREBASE_APP_NAME);
      this.messaging = getMessaging(this.app);
    } catch {
      throw new Error('Unable to initialize Firebase Admin; check FIREBASE_CREDENTIALS_PATH and service account credentials');
    }
    this.logger.log('Firebase Admin messaging initialized');
  }

  async checkAndAlert(telemetry: AlertTelemetry): Promise<void> {
    if (!telemetry?.device_id?.trim() ||
      [telemetry.temp, telemetry.humi, telemetry.wind_speed, telemetry.rain_rate].some(value => !Number.isFinite(value))) {
      this.logger.warn('Skipped notification checks: invalid telemetry');
      return;
    }
    const { tempMax, tempMin, humiMax, windMax, rainMax } = this.thresholds;
    const candidates: Array<Alert & { active: boolean }> = [
      { type: 'HIGH_TEMP', active: telemetry.temp >= tempMax, value: telemetry.temp, threshold: tempMax, unit: '°C', title: 'Cảnh báo nhiệt độ cao' },
      { type: 'LOW_TEMP', active: telemetry.temp <= tempMin, value: telemetry.temp, threshold: tempMin, unit: '°C', title: 'Cảnh báo nhiệt độ thấp' },
      { type: 'HIGH_HUMIDITY', active: telemetry.humi >= humiMax, value: telemetry.humi, threshold: humiMax, unit: '%', title: 'Cảnh báo độ ẩm cao' },
      { type: 'STRONG_WIND', active: telemetry.wind_speed >= windMax, value: telemetry.wind_speed, threshold: windMax, unit: 'm/s', title: 'Cảnh báo gió mạnh' },
      { type: 'HEAVY_RAIN', active: telemetry.rain_rate >= rainMax, value: telemetry.rain_rate, threshold: rainMax, unit: 'mm/h', title: 'Cảnh báo mưa lớn' },
    ];
    const now = Date.now();
    for (const [key, state] of this.alerts) {
      if (!state.inFlight && state.sentAt !== undefined && now - state.sentAt >= ALERT_COOLDOWN_MS) this.alerts.delete(key);
    }
    await Promise.all(candidates.filter(alert => alert.active).map(alert => this.sendAlert(telemetry.device_id, alert)));
  }

  async sendPushNotification(title: string, body: string, data?: Record<string, string>): Promise<void> {
    try {
      await this.messaging.send({ topic: this.topic, notification: { title, body }, ...(data ? { data } : {}) });
    } catch {
      this.logger.error('Failed to send FCM topic notification');
      throw new ServiceUnavailableException('Unable to send push notification');
    }
  }

  async registerToken(token: string): Promise<{ status: 'success'; message: string }> {
    if (typeof token !== 'string' || !token.trim()) throw new BadRequestException('FCM token is required');
    try {
      const result = await this.messaging.subscribeToTopic([token], this.topic);
      if (result.failureCount || result.successCount !== 1) {
        const invalidToken = result.errors.some(({ error }) =>
          ['messaging/invalid-registration-token', 'messaging/registration-token-not-registered', 'messaging/invalid-argument'].includes(error.code));
        if (invalidToken) throw new BadRequestException('Invalid or expired FCM token');
        throw new ServiceUnavailableException('Unable to subscribe FCM token');
      }
      return { status: 'success', message: 'FCM token subscribed to alert topic' };
    } catch (error: unknown) {
      this.logger.error('Failed to register FCM token');
      if (error instanceof BadRequestException || error instanceof ServiceUnavailableException) throw error;
      throw new ServiceUnavailableException('Unable to subscribe FCM token');
    }
  }

  private async sendAlert(deviceId: string, alert: Alert): Promise<void> {
    const key = `${deviceId}:${alert.type}`;
    const state = this.alerts.get(key);
    if (state?.inFlight || (state?.sentAt !== undefined && Date.now() - state.sentAt < ALERT_COOLDOWN_MS)) return;
    this.alerts.set(key, { inFlight: true });
    try {
      await this.sendPushNotification(alert.title, `Trạm ${deviceId}: ${alert.value} ${alert.unit} (ngưỡng ${alert.threshold} ${alert.unit})`, {
        device_id: deviceId,
        alert_type: alert.type,
        value: String(alert.value),
        threshold: String(alert.threshold),
      });
      this.alerts.set(key, { inFlight: false, sentAt: Date.now() });
    } catch {
      // Failed sends must allow retries and must not fail telemetry ingestion.
      this.alerts.delete(key);
    }
  }

  async onModuleDestroy(): Promise<void> {
    this.alerts.clear();
    if (this.ownsApp) await deleteApp(this.app);
  }
}
