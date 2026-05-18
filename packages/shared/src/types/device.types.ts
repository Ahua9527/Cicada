import type { DeviceId, JsonValue, Timestamp } from './common.types';

export enum DeviceCapability {
  LOCK_SCREEN = 'lock_screen',
  BLUETOOTH_CONTROL = 'bluetooth_control',
  SLEEP_CONTROL = 'sleep_control',
  SYSTEM_INFO = 'system_info',
}

export enum DeviceConnectionStatus {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  ERROR = 'error',
  TIMEOUT = 'timeout',
}

export type DeviceType = 'mac' | 'ios' | 'ipad' | 'android' | 'web' | 'unknown';

export interface DeviceInfo {
  deviceId: DeviceId;
  platform: string;
  version: string;
  sessionId?: string;
  sessionActive?: boolean;
  capabilities?: DeviceCapability[];
  deviceType?: DeviceType;
}

export interface DeviceMetadata {
  deviceId: DeviceId;
  name?: string;
  model?: string;
  osVersion?: string;
  appVersion?: string;
  capabilities: DeviceCapability[];
  lastSeen: Timestamp;
  firstSeen: Timestamp;
  attributes?: Record<string, JsonValue>;
}

export interface DeviceStatus {
  deviceId: DeviceId;
  connected: boolean;
  connectedAt?: Timestamp;
  lastPing?: Timestamp;
  uptime?: number;
  messagesExchanged?: number;
  ipAddress?: string;
  userAgent?: string;
  capabilities?: string[];
}
