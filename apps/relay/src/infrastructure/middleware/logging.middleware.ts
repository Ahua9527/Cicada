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
      context.requestId = `req_${Date.now()}_${Math.random().toString(36).slice(2, 11)}`;
    }

    const sanitizedUrl = new URL(sanitizeRequestUrl(context.url));
    const route = normalizeRoute(sanitizedUrl.pathname);

    context.logger.info(`Request started: ${context.method} ${route}`, {
      requestId: context.requestId,
      context: { method: context.method, route },
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
    const route = normalizeRoute(context.url.pathname);
    const doOperation = getDurableObjectOperation(context.url.pathname);
    const isWebSocketUpgrade =
      context.request.headers.get('Upgrade')?.toLowerCase() === 'websocket';

    const result = await next();

    const duration = Date.now() - startTime;

    const response = extractResponse(result);

    if (response) {
      const status = response.status;

      // WebSocket 升级响应（101）头部不可变，跳过日志记录以避免错误
      if (status === 101) {
        context.logger.info('WebSocket upgrade completed', {
          requestId: context.requestId,
          context: {
            route,
            status,
            duration_ms: duration,
            do_operation: doOperation,
            websocket_outcome: 'upgraded',
          },
          tags: ['websocket', 'success'],
        });
        return result;
      }

      if (status >= 400) {
        context.logger.warn(`Request failed: ${status}`, {
          requestId: context.requestId,
          context: {
            route,
            status,
            error_type: status >= 500 ? 'server_error' : 'client_error',
            duration_ms: duration,
            do_operation: doOperation,
            ...(isWebSocketUpgrade ? { websocket_outcome: 'upgrade_failed' } : {}),
          },
          tags: ['request', 'error'],
        });
      } else {
        context.logger.info(`Request completed: ${status}`, {
          requestId: context.requestId,
          context: { route, status, duration_ms: duration, do_operation: doOperation },
          tags: ['request', 'success'],
        });
      }
    } else if (isControlResult(result) && !result.continue) {
      context.logger.warn('Request completed with no response', {
        requestId: context.requestId,
        context: {
          route,
          error_type: 'missing_response',
          duration_ms: duration,
          do_operation: doOperation,
        },
        tags: ['request', 'error'],
      });
    }

    return result;
  };
}

function normalizeRoute(pathname: string): string {
  return pathname.startsWith('/relay/') ? '/relay/:liveSession' : pathname;
}

function getDurableObjectOperation(pathname: string): string | undefined {
  if (pathname.startsWith('/relay/')) {
    return 'websocket_upgrade';
  }
  if (pathname === '/v1/shortcuts/command') {
    return 'shortcut_command';
  }
  if (pathname === '/devices') {
    return 'registry_devices';
  }
  if (pathname === '/status') {
    return 'registry_status';
  }
  return undefined;
}
