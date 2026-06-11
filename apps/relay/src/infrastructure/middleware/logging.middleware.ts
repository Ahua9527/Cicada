/**
 * 日志中间件
 */

import type { Middleware } from './types';
import { extractResponse, isControlResult } from './types';
import { sanitizeRequestUrl } from '../../presentation/request-url-sanitizer';

/**
 * 生成请求ID中间件
 */
export function requestIdMiddleware(): Middleware {
  return async (context, next) => {
    // 从请求头获取或生成新的请求ID
    const existingRequestId = context.headers['x-request-id'];
    if (existingRequestId) {
      context.requestId = existingRequestId;
    } else {
      context.requestId = `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }

    const sanitizedUrl = new URL(sanitizeRequestUrl(context.url, context.env));

    context.logger.info(`Request started: ${context.method} ${sanitizedUrl.pathname}`, {
      requestId: context.requestId,
      context: { method: context.method, url: sanitizedUrl.toString() },
      tags: ['request', 'start'],
    });

    return next();
  };
}

/**
 * 请求日志中间件
 */
export function loggingMiddleware(): Middleware {
  return async (context, next) => {
    const startTime = Date.now();

    const result = await next();

    const duration = Date.now() - startTime;

    const response = extractResponse(result);

    if (response) {
      const status = response.status;

      // WebSocket 升级响应（101）头部不可变，跳过日志记录以避免错误
      if (status === 101) {
        context.logger.info('WebSocket upgrade completed', {
          requestId: context.requestId,
          context: { status, duration },
          tags: ['websocket', 'success'],
        });
        return result;
      }

      if (status >= 400) {
        context.logger.warn(`Request failed: ${status}`, {
          requestId: context.requestId,
          context: { status, duration },
          tags: ['request', 'error'],
        });
      } else {
        context.logger.info(`Request completed: ${status}`, {
          requestId: context.requestId,
          context: { status, duration },
          tags: ['request', 'success'],
        });
      }
    } else if (isControlResult(result) && !result.continue) {
      context.logger.warn('Request completed with no response', {
        requestId: context.requestId,
        context: { duration },
        tags: ['request', 'error'],
      });
    }

    return result;
  };
}
