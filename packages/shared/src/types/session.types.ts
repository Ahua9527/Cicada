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

export interface SessionStats {
  totalSessions?: number;
  activeSessions?: number;
  peakSessions?: number;
  averageSessionDuration?: number;
  totalMessages?: number;
  messagesPerSecond?: number;
  uptime?: number;
  lastCleanup?: number;
  totalConnections?: number;
  activeConnections?: number;
  connectionErrors?: number;
  authenticationErrors?: number;
}

export interface SessionHistoryEntry {
  sessionId: SessionId;
  deviceId: DeviceId;
  connectedAt: Timestamp;
  disconnectedAt?: Timestamp;
  duration?: number;
  messagesExchanged: number;
  lastPing: Timestamp;
  userAgent?: string;
  ipAddress?: string;
}

export interface SessionHistory {
  deviceId: DeviceId;
  connections: SessionHistoryEntry[];
}

export type DeviceHistory = SessionHistory;
