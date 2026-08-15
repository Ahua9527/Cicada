/**
 * 中间件系统类型定义
 */

import type { Env } from '@/types';
import type { CommandRequest } from '@cicada/shared';
import type { Logger } from '../logger';

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

/**
 * 判定 WebSocket 升级响应。生产环境 DO 经 stub.fetch() 返回的升级响应，
 * status 读取不一定为 101（真机 tail 确认 101 守卫被击穿后 headers.set 抛
 * "Can't modify immutable headers"）；附着 webSocket 才是升级响应的确定性特征。
 * 该响应头部不可变且不可重建（重建会丢失 socket），中间件必须原样透传。
 */
export function isWebSocketUpgradeResponse(response: Response): boolean {
  return (
    response.status === 101 ||
    (response as unknown as { webSocket?: unknown }).webSocket != null
  );
}
