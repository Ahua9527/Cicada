import type { JsonValue, DeviceId } from '@cicada/shared/types/common.types';
import {
  DeviceCapability,
  DeviceConnectionStatus,
  type DeviceType,
  type DeviceInfo,
  type DeviceStatus,
} from '@cicada/shared/types/device.types';

export { DeviceCapability, DeviceConnectionStatus, type DeviceType };

export class DeviceTimestamp {
  private constructor(private readonly value: number) {}

  static now(): DeviceTimestamp {
    return new DeviceTimestamp(Date.now());
  }

  static create(raw: number | null | undefined): DeviceTimestamp | null {
    return raw != null && Number.isFinite(raw) && raw >= 0 ? new DeviceTimestamp(raw) : null;
  }

  toNumber(): number {
    return this.value;
  }

  diff(other: DeviceTimestamp): number {
    return this.value - other.value;
  }
}

export type DeviceMetadata = Record<string, JsonValue> & {
  name?: string;
  model?: string;
  osVersion?: string;
  appVersion?: string;
  ipAddress?: string;
  userAgent?: string;
};

export type DeviceProps = {
  deviceId: DeviceId;
  platform: string;
  version: string;
  deviceType?: DeviceType;
  capabilities?: DeviceCapability[];
  metadata?: DeviceMetadata;
  connectionStatus?: DeviceConnectionStatus;
  connectedAt?: number | null;
  lastSeen?: number | null;
  firstSeen?: number | null;
  lastPing?: number | null;
  messagesExchanged?: number;
  uptime?: number;
  sessionId?: string | null;
};

type InternalState = {
  deviceId: DeviceId;
  platform: string;
  version: string;
  deviceType: DeviceType;
  capabilities: Set<DeviceCapability>;
  metadata: DeviceMetadata;
  connectionStatus: DeviceConnectionStatus;
  connectedAt: DeviceTimestamp | null;
  lastSeen: DeviceTimestamp;
  firstSeen: DeviceTimestamp;
  lastPing: DeviceTimestamp | null;
  messagesExchanged: number;
  uptime: number;
  sessionId: string | null;
};

export class Device {
  private state: InternalState;

  private constructor(state: InternalState) {
    this.state = state;
  }

  static create(props: DeviceProps): Device {
    const now = DeviceTimestamp.now();
    const firstSeen = DeviceTimestamp.create(props.firstSeen) ?? now;
    const lastSeen = DeviceTimestamp.create(props.lastSeen) ?? firstSeen;
    const connectedAt = DeviceTimestamp.create(props.connectedAt ?? null);
    const lastPing = DeviceTimestamp.create(props.lastPing ?? null);

    return new Device({
      deviceId: props.deviceId,
      platform: props.platform,
      version: props.version,
      deviceType: props.deviceType ?? 'unknown',
      capabilities: new Set(props.capabilities ?? []),
      metadata: { ...props.metadata },
      connectionStatus: props.connectionStatus ?? DeviceConnectionStatus.DISCONNECTED,
      connectedAt,
      lastSeen,
      firstSeen,
      lastPing,
      messagesExchanged: props.messagesExchanged ?? 0,
      uptime: props.uptime ?? 0,
      sessionId: props.sessionId ?? null,
    });
  }

  get id(): DeviceId {
    return this.state.deviceId;
  }

  get platform(): string {
    return this.state.platform;
  }

  get version(): string {
    return this.state.version;
  }

  get deviceType(): DeviceType {
    return this.state.deviceType;
  }

  get capabilities(): DeviceCapability[] {
    return Array.from(this.state.capabilities);
  }

  get metadata(): DeviceMetadata {
    return { ...this.state.metadata };
  }

  get connectionStatus(): DeviceConnectionStatus {
    return this.state.connectionStatus;
  }

  get isConnected(): boolean {
    return this.state.connectionStatus === DeviceConnectionStatus.CONNECTED;
  }

  get lastSeen(): number {
    return this.state.lastSeen.toNumber();
  }

  get sessionId(): string | null {
    return this.state.sessionId;
  }

  hasCapability(capability: DeviceCapability): boolean {
    return this.state.capabilities.has(capability);
  }

  addCapability(capability: DeviceCapability): void {
    this.state.capabilities.add(capability);
  }

  removeCapability(capability: DeviceCapability): void {
    this.state.capabilities.delete(capability);
  }

  updateMetadata(updates: Partial<DeviceMetadata>): void {
    this.state.metadata = { ...this.state.metadata, ...updates } as DeviceMetadata;
  }

  markConnected(sessionId: string, at: number = Date.now()): void {
    const timestamp = DeviceTimestamp.create(at) ?? DeviceTimestamp.now();
    this.state.connectionStatus = DeviceConnectionStatus.CONNECTED;
    this.state.connectedAt = timestamp;
    this.state.lastSeen = timestamp;
    this.state.sessionId = sessionId;
  }

  markDisconnected(at: number = Date.now()): void {
    const timestamp = DeviceTimestamp.create(at) ?? DeviceTimestamp.now();
    this.state.connectionStatus = DeviceConnectionStatus.DISCONNECTED;
    this.state.lastSeen = timestamp;
    if (this.state.connectedAt) {
      this.state.uptime += timestamp.diff(this.state.connectedAt);
    }
    this.state.connectedAt = null;
    this.state.sessionId = null;
  }

  recordPing(at: number = Date.now()): void {
    const timestamp = DeviceTimestamp.create(at) ?? DeviceTimestamp.now();
    this.state.lastPing = timestamp;
    this.state.lastSeen = timestamp;
  }

  recordMessage(at: number = Date.now()): void {
    const timestamp = DeviceTimestamp.create(at) ?? DeviceTimestamp.now();
    this.state.messagesExchanged += 1;
    this.state.lastSeen = timestamp;
  }

  hasTimedOut(timeoutMs: number, now: number = Date.now()): boolean {
    if (!this.isConnected) {
      return false;
    }
    const reference = this.state.lastPing ?? this.state.lastSeen;
    const timestamp = DeviceTimestamp.create(now) ?? DeviceTimestamp.now();
    return timestamp.diff(reference) > timeoutMs;
  }

  toDeviceInfo(): DeviceInfo {
    return {
      deviceId: this.state.deviceId,
      platform: this.state.platform,
      version: this.state.version,
      deviceType: this.state.deviceType,
      capabilities: this.capabilities,
      sessionId: this.state.sessionId ?? undefined,
      sessionActive: this.isConnected,
    };
  }

  toDeviceStatus(): DeviceStatus {
    return {
      deviceId: this.state.deviceId,
      connected: this.isConnected,
      connectedAt: this.state.connectedAt?.toNumber(),
      lastPing: this.state.lastPing?.toNumber(),
      uptime: this.state.uptime,
      messagesExchanged: this.state.messagesExchanged,
      ipAddress: this.state.metadata.ipAddress,
      userAgent: this.state.metadata.userAgent,
      capabilities: this.capabilities.map(c => c.toString()),
    };
  }
}
