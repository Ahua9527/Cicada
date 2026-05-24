/**
 * 日志中间件
 */

import type { Middleware } from './types';
import { extractResponse, isControlResult } from './types';

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

    context.logger.info(`Request started: ${context.method} ${context.url.pathname}`, {
      requestId: context.requestId,
      context: { method: context.method, url: sanitizeUrl(context.url).toString() },
      tags: ['request', 'start'],
    });

    return next();
  };
}

function sanitizeUrl(url: URL): URL {
  const safeUrl = new URL(url.toString());
  if (safeUrl.pathname.startsWith('/relay/')) {
    const [, relay, ...rest] = safeUrl.pathname.split('/');
    safeUrl.pathname = `/${relay}/[session]${rest.length > 1 ? `/${rest.slice(1).join('/')}` : ''}`;
  }
  for (const key of ['api_key', 'nonce', 'signature', 'token', 'code']) {
    if (safeUrl.searchParams.has(key)) {
      safeUrl.searchParams.set(key, '[FILTERED]');
    }
  }
  return safeUrl;
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
