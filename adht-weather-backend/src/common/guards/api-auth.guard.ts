import {
  CanActivate,
  ExecutionContext,
  Injectable,
  Optional,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { timingSafeEqual } from 'crypto';
import type { Request } from 'express';

export function safeTokenMatch(provided: string | undefined, expected: string | undefined): boolean {
  if (!provided || !expected) return false;
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

export function extractBearerOrApiKey(headers: Record<string, string | string[] | undefined>): string | undefined {
  const apiKey = headers['x-api-key'];
  if (typeof apiKey === 'string' && apiKey.trim()) {
    return apiKey.trim();
  }
  const authHeader = headers['authorization'];
  if (typeof authHeader === 'string') {
    const match = /^Bearer\s+(.+)$/i.exec(authHeader.trim());
    if (match?.[1]) {
      return match[1].trim();
    }
  }
  return undefined;
}

@Injectable()
export class ApiAuthGuard implements CanActivate {
  constructor(@Optional() private readonly configService?: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const expectedToken = this.configService?.get<string>('auth.apiToken');
    const nodeEnv = this.configService?.get<string>('nodeEnv') || process.env.NODE_ENV || 'development';

    if (!expectedToken) {
      if (nodeEnv === 'production') {
        throw new UnauthorizedException('API authentication is not configured');
      }
      return true;
    }

    const request = context.switchToHttp().getRequest<Request>();
    const provided = extractBearerOrApiKey(request.headers);
    if (!safeTokenMatch(provided, expectedToken)) {
      throw new UnauthorizedException('Invalid or missing API credentials');
    }

    return true;
  }
}
