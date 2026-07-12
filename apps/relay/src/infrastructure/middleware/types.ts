/**
 * 中间件系统类型定义
 */

import type { Env } from '@/types';
import type { Logger } from '@cicada/shared/logger';
import type { CommandRequest } from '@cicada/shared';

/**
 * 中间件上下文
 */
export interface MiddlewareContext {
  request: Request;
  env: Env;
  requestId: string;
  logger: Logger;
  timestamp: number;
  url: URL;
  method: string;
  headers: Record<string, string>;
  executionContext?: ExecutionContext;
  deviceId?: string;
  validatedRequest?: CommandRequest;
}

/**
 * 中间件控制结果
 */
export interface MiddlewareControlResult {
  continue: boolean;
  response?: Response;
}

/**
 * 中间件返回结果类型
 */
export type MiddlewareResult = MiddlewareControlResult | Response | void;

/**
 * 中间件函数类型
 */
export type Middleware = (
  context: MiddlewareContext,
  next: () => Promise<MiddlewareResult>
) => Promise<MiddlewareResult>;

/**
 * 检查是否为控制结果
 */
export function isControlResult(value: MiddlewareResult): value is MiddlewareControlResult {
  return typeof value === 'object' && value !== null && 'continue' in value;
}

/**
 * 从结果中提取响应
 */
export function extractResponse(value: MiddlewareResult): Response | undefined {
  if (value instanceof Response) {
    return value;
  }

  if (isControlResult(value) && !value.continue) {
    return value.response;
  }

  return undefined;
}
