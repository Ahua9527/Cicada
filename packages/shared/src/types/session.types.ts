import type { DeviceId, JsonValue, SessionId, Timestamp } from './common.types';

export interface SessionInfo {
  sessionId: SessionId | null;
  deviceId?: DeviceId;
  isActive: boolean;
  createdAt: Timestamp | null;
  lastActivity: Timestamp | null;
  connectedAt?: Timestamp;
  lastPing?: Timestamp;
  metadata?: Record<string, JsonValue>;
}
