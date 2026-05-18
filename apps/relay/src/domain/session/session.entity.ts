import type { JsonValue, SessionId } from '@cicada/shared/types/common.types';
import type { SessionInfo } from '@cicada/shared/types/session.types';

const DEVICE_ID_PATTERN = /^MAC_[0-9a-fA-F]{32}$/;

export enum SessionState {
  ACTIVE = 'active',
  INACTIVE = 'inactive',
  TERMINATED = 'terminated',
}

export class DeviceId {
  private constructor(private readonly value: string) {}
  static create(raw: string): DeviceId | null {
    return DEVICE_ID_PATTERN.test(raw) ? new DeviceId(raw) : null;
  }
  toString(): string {
    return this.value;
  }
  equals(other: DeviceId): boolean {
    return this.value === other.value;
  }
}

export class DomainTimestamp {
  private constructor(private readonly value: number) {}
  static now(): DomainTimestamp {
    return new DomainTimestamp(Date.now());
  }
  static create(raw: number | null | undefined): DomainTimestamp | null {
    return raw != null && Number.isFinite(raw) && raw >= 0 ? new DomainTimestamp(raw) : null;
  }
  toNumber(): number {
    return this.value;
  }
  diff(other: DomainTimestamp): number {
    return this.value - other.value;
  }
}

export type SessionMetadata = Record<string, JsonValue> & {
  ipAddress?: string;
  userAgent?: string;
};

export type SessionProps = {
  sessionId?: SessionId | null;
  deviceId: DeviceId | string;
  connectedAt?: number;
  lastActivity?: number;
  lastPing?: number | null;
  metadata?: SessionMetadata;
  totalMessages?: number;
  totalDurationMs?: number;
  timeoutCount?: number;
  cleanupRequested?: boolean;
  state?: SessionState;
};

type InternalState = {
  sessionId: SessionId | null;
  deviceId: DeviceId;
  connectedAt: DomainTimestamp;
  lastActivity: DomainTimestamp;
  lastPing: DomainTimestamp | null;
  metadata: SessionMetadata;
  state: SessionState;
  totalMessages: number;
  totalDurationMs: number;
  timeoutCount: number;
  cleanupRequested: boolean;
  activeSince: DomainTimestamp;
};

export class Session {
  private state: InternalState;

  private constructor(state: InternalState) {
    this.state = state;
  }

  static create(props: SessionProps): Session {
    const connectedAt = DomainTimestamp.create(props.connectedAt) ?? DomainTimestamp.now();
    const lastActivity = DomainTimestamp.create(props.lastActivity) ?? connectedAt;
    const lastPing = DomainTimestamp.create(props.lastPing ?? null);
    const metadata: SessionMetadata = { ...props.metadata };

    // Convert string deviceId to DeviceId class if needed
    const deviceId =
      typeof props.deviceId === 'string'
        ? (DeviceId.create(props.deviceId) ??
          (() => {
            throw new Error(`Invalid device ID: ${props.deviceId}`);
          })())
        : props.deviceId;

    return new Session({
      sessionId: props.sessionId ?? null,
      deviceId,
      connectedAt,
      lastActivity,
      lastPing,
      metadata,
      state: props.state ?? SessionState.ACTIVE,
      totalMessages: props.totalMessages ?? 0,
      totalDurationMs: props.totalDurationMs ?? 0,
      timeoutCount: props.timeoutCount ?? 0,
      cleanupRequested: props.cleanupRequested ?? false,
      activeSince: lastActivity,
    });
  }

  get id(): SessionId | null {
    return this.state.sessionId;
  }

  get device(): DeviceId {
    return this.state.deviceId;
  }

  get metadata(): SessionMetadata {
    return { ...this.state.metadata };
  }

  get isActive(): boolean {
    return this.state.state === SessionState.ACTIVE;
  }

  get lastActivity(): number {
    return this.state.lastActivity.toNumber();
  }

  get lastPing(): number | null {
    return this.state.lastPing?.toNumber() ?? null;
  }

  get connectedAt(): number {
    return this.state.connectedAt.toNumber();
  }

  get messagesExchanged(): number {
    return this.state.totalMessages;
  }

  get deviceId(): string {
    return this.state.deviceId.toString();
  }

  recordMessage(at: number = Date.now()): void {
    this.state.totalMessages += 1;
    this.updateActivity(at);
  }

  recordPing(at: number = Date.now()): void {
    this.state.lastPing = DomainTimestamp.create(at) ?? DomainTimestamp.now();
    this.updateActivity(at);
  }

  updateActivity(at: number = Date.now()): void {
    const timestamp = DomainTimestamp.create(at) ?? DomainTimestamp.now();
    this.state.lastActivity = timestamp;
    if (this.state.state === SessionState.INACTIVE) {
      this.markActive(at);
    }
  }

  markActive(at: number = Date.now()): void {
    const timestamp = DomainTimestamp.create(at) ?? DomainTimestamp.now();
    this.state.state = SessionState.ACTIVE;
    this.state.lastActivity = timestamp;
    this.state.activeSince = timestamp;
    this.state.cleanupRequested = false;
  }

  markInactive(at: number = Date.now()): void {
    const timestamp = DomainTimestamp.create(at) ?? DomainTimestamp.now();
    if (this.state.state === SessionState.ACTIVE) {
      this.state.totalDurationMs += timestamp.diff(this.state.activeSince);
    }
    this.state.state = SessionState.INACTIVE;
    this.state.lastActivity = timestamp;
    this.state.cleanupRequested = true;
  }

  hasTimedOut(timeoutMs: number, now: number = Date.now()): boolean {
    const reference = this.state.lastPing ?? this.state.lastActivity;
    const timestamp = DomainTimestamp.create(now) ?? DomainTimestamp.now();
    if (timestamp.diff(reference) > timeoutMs) {
      if (this.state.state === SessionState.ACTIVE) {
        this.state.timeoutCount += 1;
      }
      this.markInactive(timestamp.toNumber());
      return true;
    }
    return false;
  }

  getMetrics(): { totalMessages: number; totalDurationMs: number; timeoutCount: number } {
    return {
      totalMessages: this.state.totalMessages,
      totalDurationMs: this.state.totalDurationMs,
      timeoutCount: this.state.timeoutCount,
    };
  }

  needsCleanup(): boolean {
    return this.state.cleanupRequested;
  }

  toSessionInfo(): SessionInfo {
    return {
      sessionId: this.state.sessionId,
      deviceId: this.state.deviceId.toString(),
      isActive: this.isActive,
      createdAt: this.state.connectedAt.toNumber(),
      lastActivity: this.state.lastActivity.toNumber(),
      connectedAt: this.state.connectedAt.toNumber(),
      lastPing: this.state.lastPing?.toNumber(),
      metadata: this.state.metadata,
    };
  }
}
