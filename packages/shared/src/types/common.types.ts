import type { DurableObjectNamespace } from '@cloudflare/workers-types';

/**
 * Shared primitive and infrastructure types used across Cicada and CicadaRelay.
 */

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonObject | JsonArray;
export interface JsonObject {
  [key: string]: JsonValue;
}
export type JsonArray = JsonValue[];

export type DeviceId = string;
export type SessionId = string;
export type Timestamp = number;

/**
 * Standard API response envelope used by both products.
 */
export interface ApiResponse<T = unknown> {
  ok: boolean;
  success?: boolean;
  data?: T;
  code?: string;
  error?: string;
  message?: string;
  timestamp?: number;
  requestId?: string;
  request_id?: string;
}

/**
 * Pagination metadata shared by list endpoints.
 */
export interface PaginatedResponse<T = unknown> extends ApiResponse<T> {
  pagination?: {
    page: number;
    pageSize: number;
    total: number;
    hasMore: boolean;
  };
}

/**
 * Structured error detail payload for validation/command failures.
 */
export interface ErrorDetail {
  code: string;
  message: string;
  field?: string;
  details?: JsonValue;
}

/**
 * Runtime configuration exposed to Cloudflare Workers environment bindings.
 */
export interface Env {
  CICADA_SESSIONS: DurableObjectNamespace;

  NODE_ENV?: string;
  LOG_LEVEL?: string;
  ENABLE_CORS?: string;
  MAX_CONCURRENT_SESSIONS?: string;
  RATE_LIMIT_ENABLED?: string;
  SESSION_TIMEOUT?: string;
  DEBUG_MODE?: string;
  ENABLE_CONSOLE_LOG?: string;
  ENABLE_STRUCTURED_LOG?: string;
  WS_PING_INTERVAL?: string;
  WS_PONG_TIMEOUT?: string;
  ENABLE_METRICS?: string;
  ENABLE_HEALTH_CHECKS?: string;
  ENABLE_COMPRESSION?: string;
  ENABLE_CACHING?: string;
  ALLOWED_ORIGINS?: string;
  USE_DDD_ARCHITECTURE?: string;
}

/**
 * Worker socket level metadata tracked by CicadaRelay.
 */
export interface WebSocketInfo {
  deviceId: DeviceId;
  connectedAt: number;
  lastPing: number;
  isActive: boolean;
  userAgent?: string;
  ipAddress?: string;
}

export interface HealthStatus {
  status: 'healthy' | 'unhealthy' | 'degraded';
  version: string;
  uptime: number;
  timestamp: number;
  checks: {
    durable_objects: boolean;
    memory_usage: boolean;
    active_sessions: number;
  };
  metrics?: {
    total_requests: number;
    error_rate: number;
    avg_response_time: number;
  };
}

export interface CicadaAgentConfig {
  relayURL: string;
  deviceId: string;
  autoConnect: boolean;
  showNotifications: boolean;
  enableAutoReconnect?: boolean;
  reconnectInterval?: number;
  maxReconnectAttempts?: number;
  heartbeatInterval?: number;
  connectionTimeout?: number;
}

export interface ConnectionQuality {
  isConnected: boolean;
  errorCount: number;
  reconnectAttempts: number;
  lastError?: string;
  lastErrorTime?: number;
  averageErrorInterval: number;
}

export interface PerformanceMetrics {
  renderCount: number;
  averageRenderTime: number;
  memoryUsage: number;
  lastRenderTime: number;
  componentRerenders: Record<string, number>;
}

export type Timer = ReturnType<typeof setTimeout>;
