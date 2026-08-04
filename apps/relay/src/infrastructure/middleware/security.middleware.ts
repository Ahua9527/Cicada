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
 *
 * M11: 不再仅依赖 content-length 头（可被绕过）。合法且超限的 content-length
 * 早退 413；其余所有请求体（含 content-length 缺失/畸形/少报）一律流式
 * 累计实际字节数，超限即中断并返回 413；未超限则用缓冲重建 request 供下游
 * 消费。
 */
export function requestSizeLimitMiddleware(options: { maxSize?: number } = {}): Middleware {
  const maxSize = options.maxSize ?? 10 * 1024; // 默认 10KB

  return async (context, next) => {
    // 只检查有请求体的方法
    if (context.method === 'POST' || context.method === 'PUT' || context.method === 'PATCH') {
      const contentLength = context.request.headers.get('content-length');

      if (contentLength !== null) {
        const size = parseInt(contentLength, 10);
        if (Number.isFinite(size) && size > maxSize) {
          const sanitizedUrl = new URL(sanitizeRequestUrl(context.url));
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

      // 其余所有请求体（content-length 缺失/畸形/少报）：流式累计实际字节，超限中断
      if (context.request.body) {
        const reader = context.request.body.getReader();
        const chunks: BlobPart[] = [];
        let total = 0;
        try {
          for (;;) {
            const { done, value } = await reader.read();
            if (done) {
              break;
            }
            if (value) {
              total += value.byteLength;
              if (total > maxSize) {
                await reader.cancel();
                const sanitizedUrl = new URL(sanitizeRequestUrl(context.url));
                context.logger.warn('Request body exceeded limit (streamed)', {
                  requestId: context.requestId,
                  context: {
                    size: total,
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
                        receivedSize: total,
                      },
                    },
                    { status: 413 }
                  ),
                };
              }
              chunks.push(value as unknown as BlobPart);
            }
          }
        } finally {
          reader.releaseLock();
        }

        // 用缓冲重建 request，下游可再次读取 body；去掉原始 content-length
        // （可能少报/畸形），让新 Request 按实际 body 长度重算。
        const rebuiltHeaders = new Headers(context.request.headers);
        rebuiltHeaders.delete('content-length');
        const rebuiltBody = new Blob(chunks);
        context.request = new Request(context.request.url, {
          method: context.request.method,
          headers: rebuiltHeaders,
          body: rebuiltBody,
        });
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
