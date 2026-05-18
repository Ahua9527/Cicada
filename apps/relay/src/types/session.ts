import type { JsonValue } from '@cicada/shared';
import { WebSocketInfo } from './common';

/**
 * 会话配置
 */
export interface SessionConfig {
  timeout: number; // 会话超时时间（毫秒）
  cleanupInterval: number; // 清理间隔（毫秒）
  maxConcurrentSessions: number; // 最大并发会话数
  heartbeatInterval: number; // 心跳间隔（毫秒）
  messageHistorySize: number; // 消息历史保留大小
  enableCompression: boolean; // 是否启用压缩
  enableMetrics: boolean; // 是否启用指标收集
}

/**
 * 会话状态
 */
export type SessionState = 'connecting' | 'connected' | 'disconnected' | 'suspended' | 'error';

/**
 * 增强的会话信息
 */
export interface EnhancedSessionInfo extends WebSocketInfo {
  sessionId: string;
  state: SessionState;
  lastActivity: number;
  messageCount: number;
  bytesReceived: number;
  bytesSent: number;
  compressionEnabled: boolean;
  metrics?: SessionMetrics;
  metadata?: Record<string, JsonValue>;
}

/**
 * 会话指标
 */
export interface SessionMetrics {
  messagesPerSecond: number;
  averageLatency: number;
  errorRate: number;
  reconnectionCount: number;
  lastError?: string;
  lastErrorTime?: number;
}

/**
 * 消息队列项
 */
export interface QueuedMessage {
  id: string;
  sessionId: string;
  deviceId: string;
  payload: JsonValue;
  timestamp: number;
  priority: number;
  retries: number;
  maxRetries: number;
  expiresAt?: number;
}

/**
 * 会话事件
 */
export interface SessionEvent {
  type: 'connect' | 'disconnect' | 'message' | 'error' | 'timeout' | 'heartbeat';
  sessionId: string;
  deviceId: string;
  timestamp: number;
  data?: JsonValue;
  metadata?: Record<string, JsonValue>;
}

/**
 * 会话过滤器
 */
export interface SessionFilter {
  deviceId?: string;
  state?: SessionState;
  connectedAfter?: number;
  connectedBefore?: number;
  hasActivityAfter?: number;
  limit?: number;
  offset?: number;
}

/**
 * 会话统计数据
 */
export interface SessionStatistics {
  totalSessions: number;
  activeSessions: number;
  peakSessions: number;
  averageSessionDuration: number;
  totalMessages: number;
  totalBytesTransferred: number;
  connectionSuccessRate: number;
  errorRate: number;
  reconnectionRate: number;
  lastReset: number;
  uptime: number;
}

/**
 * 会话管理选项
 */
export interface SessionManagerOptions {
  config?: Partial<SessionConfig>;
  enablePersistence?: boolean;
  enableMetrics?: boolean;
  enableEvents?: boolean;
  customValidators?: Array<(session: EnhancedSessionInfo) => boolean>;
  hooks?: {
    beforeConnect?: (deviceId: string, metadata?: Record<string, JsonValue>) => Promise<boolean>;
    afterConnect?: (session: EnhancedSessionInfo) => Promise<void>;
    beforeDisconnect?: (session: EnhancedSessionInfo) => Promise<void>;
    afterDisconnect?: (session: EnhancedSessionInfo) => Promise<void>;
    onMessage?: (session: EnhancedSessionInfo, message: JsonValue) => Promise<void>;
    onError?: (session: EnhancedSessionInfo, error: Error) => Promise<void>;
  };
}

/**
 * 会话存储键
 */
export interface SessionStorageKeys {
  CICADA_SESSIONS: string;
  METADATA: string;
  NONCES: string;
  MESSAGES: string;
  STATS: string;
  CONFIG: string;
  EVENTS: string;
}

/**
 * 批量操作结果
 */
export interface BatchOperationResult<T = JsonValue> {
  successful: Array<{
    id: string;
    result: T;
  }>;
  failed: Array<{
    id: string;
    error: string;
  }>;
  summary: {
    total: number;
    successful: number;
    failed: number;
    duration: number;
  };
}

/**
 * 会话健康检查结果
 */
export interface SessionHealthCheck {
  sessionId: string;
  deviceId: string;
  status: 'healthy' | 'unhealthy' | 'degraded';
  checks: {
    websocket: boolean;
    heartbeat: boolean;
    messageQueue: boolean;
    storage: boolean;
  };
  lastCheck: number;
  issues: string[];
  recommendations: string[];
}
