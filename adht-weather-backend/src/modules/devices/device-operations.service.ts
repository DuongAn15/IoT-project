import {
  BadRequestException,
  ConflictException,
  Injectable,
  Logger,
  NotFoundException,
  Optional,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createHash, randomUUID } from 'crypto';
import * as fs from 'fs';
import * as path from 'path';
import type { SendCommandDto } from './dto/send-command.dto';
import type { UpdateConfigDto } from './dto/update-config.dto';

export type OperationKind = 'config' | 'command';
export type OperationStatus =
  | 'queued'
  | 'published'
  | 'accepted'
  | 'persisted'
  | 'applied'
  | 'failed'
  | 'expired';

export interface StationConfigSnapshot {
  temp_max: number;
  temp_min: number;
  humi_max: number;
  wind_max: number;
  rain_max: number;
  auto_warning: boolean;
  buzzer: boolean;
}

export interface OperationRecord {
  operation_id: string;
  device_id: string;
  kind: OperationKind;
  status: OperationStatus;
  desired_version?: number;
  snapshot?: StationConfigSnapshot;
  payload: Record<string, unknown>;
  payload_hash: string;
  deployment_id?: string;
  request_id?: string;
  expires_at: string;
  created_at: string;
  updated_at: string;
  broker_acked_at?: string;
  device_acked_at?: string;
  ack_boot_id?: string;
  error_code?: string;
  error_message?: string;
}

export interface StationOperationState {
  device_id: string;
  desired_version: number;
  desired_config: StationConfigSnapshot;
  reported_version: number;
  reported_config: StationConfigSnapshot | null;
  last_ack_at?: string;
}

interface PersistedLedgerState {
  stations: Record<string, StationOperationState>;
  operations: Record<string, OperationRecord>;
}

export interface DeviceAckPayload {
  request_id?: string;
  device_id?: string;
  deployment_id?: string;
  boot_id?: string;
  kind?: OperationKind;
  status?: 'accepted' | 'persisted' | 'applied' | 'failed' | 'rejected';
  version?: number;
  error_code?: string;
  error_message?: string;
  config?: Partial<StationConfigSnapshot>;
}

const DEFAULT_CONFIG: StationConfigSnapshot = {
  temp_max: 38.0,
  temp_min: 10.0,
  humi_max: 90.0,
  wind_max: 15.0,
  rain_max: 30.0,
  auto_warning: true,
  buzzer: true,
};

const TERMINAL_STATUSES = new Set<OperationStatus>(['applied', 'failed', 'expired']);
const MAX_RECENT_OPS = 200;

@Injectable()
export class DeviceOperationsService {
  private readonly logger = new Logger(DeviceOperationsService.name);
  private readonly stations = new Map<string, StationOperationState>();
  private readonly operations = new Map<string, OperationRecord>();
  private readonly requestIndex = new Map<string, string>();
  private readonly ledgerFile?: string;

  constructor(@Optional() private readonly configService?: ConfigService) {
    this.ledgerFile =
      this.configService?.get<string>('OPERATION_LEDGER_FILE') ??
      process.env.OPERATION_LEDGER_FILE ??
      path.join(process.cwd(), 'data', 'operation-ledger.json');
    this.loadLedger();
  }

  private opKey(deviceId: string, operationId: string): string {
    return `${deviceId}:${operationId}`;
  }

  private loadLedger(): void {
    if (!this.ledgerFile || !fs.existsSync(this.ledgerFile)) return;
    try {
      const raw = JSON.parse(fs.readFileSync(this.ledgerFile, 'utf8')) as PersistedLedgerState;
      for (const [id, st] of Object.entries(raw.stations || {})) {
        this.stations.set(id, st);
      }
      for (const [, op] of Object.entries(raw.operations || {})) {
        const key = this.opKey(op.device_id, op.operation_id);
        this.operations.set(key, op);
        if (op.request_id) {
          this.requestIndex.set(this.opKey(op.device_id, op.request_id), key);
        }
      }
    } catch {
      this.logger.warn('Failed to load operation ledger file; starting fresh');
    }
  }

  private saveLedger(throwOnError = false): void {
    if (!this.ledgerFile) return;
    try {
      fs.mkdirSync(path.dirname(this.ledgerFile), { recursive: true });
      const data: PersistedLedgerState = {
        stations: Object.fromEntries(this.stations.entries()),
        operations: Object.fromEntries(this.operations.entries()),
      };
      const tmpFile = `${this.ledgerFile}.tmp`;
      fs.writeFileSync(tmpFile, JSON.stringify(data));
      fs.renameSync(tmpFile, this.ledgerFile);
    } catch (error) {
      this.logger.error('Failed to persist operation ledger file');
      if (throwOnError) {
        throw new ServiceUnavailableException('Unable to persist operation ledger');
      }
    }
  }

  private getOrCreateStationState(deviceId: string): StationOperationState {
    let state = this.stations.get(deviceId);
    if (!state) {
      state = {
        device_id: deviceId,
        desired_version: 0,
        desired_config: { ...DEFAULT_CONFIG },
        reported_version: 0,
        reported_config: null,
      };
      this.stations.set(deviceId, state);
    }
    return state;
  }

  private hashPayload(value: unknown): string {
    return createHash('sha256').update(JSON.stringify(value)).digest('hex');
  }

  private resolveDeploymentId(deviceId: string): string | undefined {
    const deployments = this.configService?.get<Record<string, string>>('auth.deviceDeployments');
    return deployments?.[deviceId];
  }

  private refreshExpiry(op: OperationRecord): OperationRecord {
    if (!TERMINAL_STATUSES.has(op.status) && Date.now() > Date.parse(op.expires_at)) {
      op.status = 'expired';
      op.updated_at = new Date().toISOString();
      this.saveLedger();
    }
    return op;
  }

  private trimLedger(): void {
    if (this.operations.size <= MAX_RECENT_OPS) return;
    const keys = [...this.operations.keys()];
    for (const key of keys.slice(0, keys.length - MAX_RECENT_OPS)) {
      const removed = this.operations.get(key);
      if (removed?.request_id) {
        this.requestIndex.delete(`${removed.device_id}:${removed.request_id}`);
      }
      this.operations.delete(key);
    }
  }

  createCommandOperation(
    deviceId: string,
    dto: SendCommandDto,
  ): { operation: OperationRecord; duplicate: boolean } {
    const normalizedPayload = {
      cmd: dto.cmd,
      ...(dto.arg !== undefined ? { arg: dto.arg } : {}),
    };
    const payloadHash = this.hashPayload({ kind: 'command', ...normalizedPayload });

    if (dto.request_id) {
      const existingKey = this.requestIndex.get(this.opKey(deviceId, dto.request_id));
      const existing = existingKey ? this.operations.get(existingKey) : undefined;
      if (existing) {
        if (existing.payload_hash !== payloadHash) {
          throw new ConflictException('request_id already used with a different command payload');
        }
        return { operation: this.refreshExpiry(existing), duplicate: true };
      }
    }

    const now = Date.now();
    const ttlMs = (dto.ttl_seconds ?? 60) * 1000;
    const opId = dto.request_id?.trim() || `cmd-${randomUUID()}`;
    const key = this.opKey(deviceId, opId);
    const op: OperationRecord = {
      operation_id: opId,
      device_id: deviceId,
      kind: 'command',
      status: 'queued',
      payload: normalizedPayload,
      payload_hash: payloadHash,
      deployment_id: this.resolveDeploymentId(deviceId),
      ...(dto.request_id ? { request_id: dto.request_id } : {}),
      expires_at: new Date(now + ttlMs).toISOString(),
      created_at: new Date(now).toISOString(),
      updated_at: new Date(now).toISOString(),
    };
    this.operations.set(key, op);
    if (dto.request_id) {
      this.requestIndex.set(this.opKey(deviceId, dto.request_id), key);
    }
    this.trimLedger();
    try {
      this.saveLedger(true);
    } catch (error) {
      this.operations.delete(key);
      if (dto.request_id) {
        this.requestIndex.delete(this.opKey(deviceId, dto.request_id));
      }
      throw error;
    }
    return { operation: op, duplicate: false };
  }

  createConfigOperation(
    deviceId: string,
    dto: UpdateConfigDto,
  ): { operation: OperationRecord; duplicate: boolean; mergedConfig: StationConfigSnapshot } {
    const station = this.getOrCreateStationState(deviceId);
    const patch: Partial<StationConfigSnapshot> = {};
    if (dto.temp_max !== undefined) patch.temp_max = dto.temp_max;
    if (dto.temp_min !== undefined) patch.temp_min = dto.temp_min;
    if (dto.humi_max !== undefined) patch.humi_max = dto.humi_max;
    if (dto.wind_max !== undefined) patch.wind_max = dto.wind_max;
    if (dto.rain_max !== undefined) patch.rain_max = dto.rain_max;
    if (dto.auto_warning !== undefined) patch.auto_warning = dto.auto_warning;
    if (dto.buzzer !== undefined) patch.buzzer = dto.buzzer;

    const payloadHash = this.hashPayload({
      kind: 'config',
      patch,
      expected_version: dto.expected_version,
    });

    if (dto.request_id) {
      const existingKey = this.requestIndex.get(this.opKey(deviceId, dto.request_id));
      const existing = existingKey ? this.operations.get(existingKey) : undefined;
      if (existing) {
        if (existing.payload_hash !== payloadHash) {
          throw new ConflictException('request_id already used with a different config payload');
        }
        return {
          operation: this.refreshExpiry(existing),
          duplicate: true,
          mergedConfig: existing.snapshot ?? station.desired_config,
        };
      }
    }

    if (dto.expected_version !== undefined && dto.expected_version !== station.desired_version) {
      throw new ConflictException({
        message: `Config version conflict: expected ${dto.expected_version}, current is ${station.desired_version}`,
        current_version: station.desired_version,
        desired_config: station.desired_config,
      });
    }

    const merged: StationConfigSnapshot = {
      ...station.desired_config,
      ...patch,
    };
    if (merged.temp_min >= merged.temp_max) {
      throw new BadRequestException(
        `Merged config invalid: temp_min (${merged.temp_min}) must be strictly less than temp_max (${merged.temp_max})`,
      );
    }

    const prevVersion = station.desired_version;
    const prevConfig = { ...station.desired_config };
    const nextVersion = prevVersion + 1;
    station.desired_version = nextVersion;
    station.desired_config = merged;

    const now = Date.now();
    const opId = dto.request_id?.trim() || `cfg-${randomUUID()}`;
    const key = this.opKey(deviceId, opId);
    const op: OperationRecord = {
      operation_id: opId,
      device_id: deviceId,
      kind: 'config',
      status: 'queued',
      desired_version: nextVersion,
      snapshot: { ...merged },
      payload: { ...patch },
      payload_hash: payloadHash,
      deployment_id: this.resolveDeploymentId(deviceId),
      ...(dto.request_id ? { request_id: dto.request_id } : {}),
      expires_at: new Date(now + 300_000).toISOString(),
      created_at: new Date(now).toISOString(),
      updated_at: new Date(now).toISOString(),
    };
    this.operations.set(key, op);
    if (dto.request_id) {
      this.requestIndex.set(this.opKey(deviceId, dto.request_id), key);
    }
    this.trimLedger();
    try {
      this.saveLedger(true);
    } catch (error) {
      station.desired_version = prevVersion;
      station.desired_config = prevConfig;
      this.operations.delete(key);
      if (dto.request_id) {
        this.requestIndex.delete(this.opKey(deviceId, dto.request_id));
      }
      throw error;
    }
    return { operation: op, duplicate: false, mergedConfig: merged };
  }

  markPublishResult(deviceId: string, operationId: string, published: boolean): OperationRecord | undefined {
    const op = this.operations.get(this.opKey(deviceId, operationId));
    if (!op) return undefined;
    const nowIso = new Date().toISOString();
    if (published) {
      op.broker_acked_at = nowIso;
    }
    // Never overwrite a status already reported by the device or already terminal.
    if (op.status === 'queued') {
      // A missing PUBACK is ambiguous: the broker may already have delivered the message.
      // Keep the same request ID in the outbox and retry until expiry.
      op.status = published ? 'published' : 'queued';
      if (!published) {
        op.error_code = 'broker_publish_unknown';
        op.error_message = 'Awaiting broker receipt; retry with the same request ID';
      } else {
        delete op.error_code;
        delete op.error_message;
      }
      op.updated_at = nowIso;
      this.saveLedger();
    } else if (published) {
      op.updated_at = nowIso;
      this.saveLedger();
    }
    return op;
  }

  async recoverPendingOutbox(
    publishFn: (op: OperationRecord) => Promise<boolean>,
  ): Promise<number> {
    let publishedCount = 0;
    for (const op of this.operations.values()) {
      this.refreshExpiry(op);
      if (op.status !== 'queued') continue;
      try {
        const ok = await publishFn(op);
        this.markPublishResult(op.device_id, op.operation_id, ok);
        if (ok) publishedCount++;
      } catch {
        // Keep operation in 'queued' state so a subsequent reconnect can retry it.
      }
    }
    return publishedCount;
  }

  handleDeviceAck(topicDeviceId: string, ack: DeviceAckPayload): OperationRecord | null {
    if (!ack?.request_id || typeof ack.request_id !== 'string') {
      return null;
    }
    if (ack.device_id && ack.device_id !== topicDeviceId) {
      this.logger.warn(`Rejected ACK: topic device ${topicDeviceId} != payload device ${ack.device_id}`);
      return null;
    }

    const op = this.operations.get(this.opKey(topicDeviceId, ack.request_id));
    if (!op) {
      return null;
    }

    if (ack.kind !== undefined && ack.kind !== op.kind) {
      this.logger.warn(`Rejected ACK for ${op.operation_id}: kind ${ack.kind} != ${op.kind}`);
      return null;
    }

    this.refreshExpiry(op);
    if (TERMINAL_STATUSES.has(op.status)) {
      return op;
    }

    const expectedDeployment = op.deployment_id ?? this.resolveDeploymentId(topicDeviceId);
    if (expectedDeployment && ack.deployment_id !== expectedDeployment) {
      this.logger.warn(`Ignored stale/mismatched ACK for ${op.operation_id}: deployment mismatch`);
      return null;
    }

    if (
      op.kind === 'config' &&
      op.desired_version !== undefined &&
      ack.version !== op.desired_version
    ) {
      this.logger.warn(`Ignored config ACK with missing/mismatched version ${String(ack.version)} != ${op.desired_version}`);
      return null;
    }

    const nowIso = new Date().toISOString();
    if (ack.status === 'accepted') {
      op.status = 'accepted';
    } else if (ack.status === 'persisted') {
      op.status = 'persisted';
    } else if (ack.status === 'applied') {
      op.status = 'applied';
    } else if (ack.status === 'failed' || ack.status === 'rejected') {
      op.status = 'failed';
      op.error_code = ack.error_code || ack.status;
      op.error_message = ack.error_message || 'Device rejected or failed operation';
    } else {
      return null;
    }

    op.device_acked_at = nowIso;
    if (ack.boot_id) {
      op.ack_boot_id = ack.boot_id;
    }
    op.updated_at = nowIso;

    if (op.kind === 'config' && (op.status === 'persisted' || op.status === 'applied')) {
      const station = this.getOrCreateStationState(topicDeviceId);
      const ackVer = ack.version ?? op.desired_version ?? station.reported_version;
      if (ackVer >= station.reported_version) {
        station.reported_version = ackVer;
        const baseSnapshot = op.snapshot ?? station.reported_config ?? { ...DEFAULT_CONFIG };
        station.reported_config = ack.config
          ? { ...baseSnapshot, ...ack.config }
          : { ...baseSnapshot };
        station.last_ack_at = nowIso;
      }
    }

    this.saveLedger();
    return op;
  }

  getStationState(deviceId: string) {
    const station = this.getOrCreateStationState(deviceId);
    const recentOperations = [...this.operations.values()]
      .filter((op) => op.device_id === deviceId)
      .map((op) => this.refreshExpiry(op))
      .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))
      .slice(0, 20);
    return {
      ...station,
      recent_operations: recentOperations,
    };
  }

  getOperation(deviceId: string, operationId: string): OperationRecord {
    const op = this.operations.get(this.opKey(deviceId, operationId));
    if (!op) {
      throw new NotFoundException(`Operation ${operationId} not found for ${deviceId}`);
    }
    return this.refreshExpiry(op);
  }
}
