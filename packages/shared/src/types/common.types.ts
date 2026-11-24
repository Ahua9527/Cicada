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
 * Runtime configuration exposed to Cloudflare Workers environment bindings.
 */
export interface Env {
  CICADA_SESSIONS: DurableObjectNamespace;

  NODE_ENV?: string;
  LOG_LEVEL?: string;
  ENABLE_CORS?: string;
  RATE_LIMIT_ENABLED?: string;
  DEBUG_MODE?: string;
  ALLOWED_ORIGINS?: string;
  /** 运维管理端点令牌（/v1/admin/*）。未配置时管理端点关闭（404）。 */
  CICADA_ADMIN_TOKEN?: string;
}

export type Timer = ReturnType<typeof setTimeout>;
