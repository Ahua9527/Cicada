/**
 * CicadaRelay 统一类型定义导出
 *
 * 本文件作为所有类型定义的统一入口点，提供完整的类型系统
 */

// 基础类型
export * from './common';

// 模型类型（包含枚举）
export * from './models';

// API相关类型
export * from './api';

// 会话相关类型
export * from './session';

// 中间件类型（从infrastructure/middleware模块导出）
export type {
  MiddlewareContext,
  Middleware,
  MiddlewareResult,
} from '../infrastructure/middleware/types';

// 重新导出常用类型，方便直接使用
export type {
  // 环境和基础类型
  Env,
  ApiResponse,
  WebSocketInfo,
  HealthStatus,
} from './common';

// 从 api.ts 导出 API 类型
export type {
  CommandRequest,
  WebSocketMessage,
  DeviceStatus,
  CommandResponse,
  SystemStatusResponse,
  DeviceListResponse,
} from './api';

// 从 session.ts 导出会话类型
export type { EnhancedSessionInfo } from './session';

// 日志类型
export type { LogEntry } from '../utils/logger';

// 重新导出枚举（必须作为值导出才能在运行时使用）
export type { LogLevel } from './models';
export { ErrorType, DeviceConnectionStatus, DeviceCapability } from './models';

// 重新导出类型
export type {
  SessionInfo,
  WSMessage,
  CommandResult,
  DeviceMetadata,
  SessionStats,
  RateLimitConfig,
} from './models';

export type { DeviceId, SessionId, Timestamp, JsonValue, JsonObject, JsonArray } from './common';

export type {
  RelayTransportMessage,
  RelayControlMessage,
  ShortcutGrantRecord,
  ShortcutCommandRequest,
  ShortcutCommandResponse,
} from '@cicada/shared';
export { RELAY_CLOSE_CODES } from '@cicada/shared';
