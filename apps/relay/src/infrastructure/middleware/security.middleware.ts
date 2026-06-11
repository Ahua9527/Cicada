/**
 * 安全中间件
 */

import type { Middleware, MiddlewareResult } from './types';
import { extractResponse } from './types';
import { sanitizeRequestUrl } from '../../presentation/request-url-sanitizer';

/**
 * 安全头中间件
 */
export function securityHeadersMiddleware(): Middleware {
  return async (context, next) => {
    const result = await next();

    const response = extractResponse(result);
    if (!response) {
      return result;
    }

    // WebSocket 升级响应（101）头部不可变，直接返回
    if (response.status === 101) {
      return result;
    }

    const securityHeaders: Record<string, string> = {
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'X-XSS-Protection': '1; mode=block',
      'Referrer-Policy': 'strict-origin-when-cross-origin',
      'Content-Security-Policy': "default-src 'self'",
    };

    return addSecurityHeaders(result, securityHeaders);
  };
}

/**
 * 请求体大小限制中间件
 */
export function requestSizeLimitMiddleware(options: { maxSize?: number } = {}): Middleware {
  const maxSize = options.maxSize ?? 10 * 1024; // 默认 10KB

  return async (context, next) => {
    // 只检查有请求体的方法
    if (context.method === 'POST' || context.method === 'PUT' || context.method === 'PATCH') {
      const contentLength = context.request.headers.get('content-length');

      if (contentLength) {
        const size = parseInt(contentLength);
        if (size > maxSize) {
          const sanitizedUrl = new URL(sanitizeRequestUrl(context.url, context.env));
          context.logger.warn('Request body too large', {
            requestId: context.requestId,
            context: {
              size,
              maxSize,
              method: context.method,
              path: sanitizedUrl.pathname,
            },
            tags: ['security', 'request-size'],
          });

          return {
            continue: false,
            response: Response.json(
              {
                ok: false,
                error: '请求体过大',
                details: {
                  maxSize,
                  receivedSize: size,
                },
              },
              { status: 413 }
            ),
          };
        }
      }
    }

    return next();
  };
}

/**
 * 添加安全头到响应
 */
function addSecurityHeaders(
  result: MiddlewareResult,
  headers: Record<string, string>
): MiddlewareResult {
  if (result instanceof Response) {
    const newHeaders = new Headers(result.headers);
    Object.entries(headers).forEach(([key, value]) => {
      if (!newHeaders.has(key)) {
        newHeaders.set(key, value);
      }
    });

    return new Response(result.body, {
      status: result.status,
      statusText: result.statusText,
      headers: newHeaders,
    });
  }

  return result;
}
