/**
 * 限流中间件
 */

import type { Middleware, MiddlewareContext } from './types';
import { extractResponse } from './types';

export interface RateLimitOptions {
  windowMs: number;
  maxRequests: number;
  keyGenerator?: (context: MiddlewareContext) => string;
}

/**
 * 限流中间件
 */
export function rateLimitMiddleware(options: RateLimitOptions): Middleware {
  const { windowMs, maxRequests, keyGenerator } = options;
  const requests = new Map<string, { count: number; resetTime: number }>();

  return async (context, next) => {
    const key = keyGenerator ? keyGenerator(context) : getClientIdentifier(context);
    const now = Date.now();

    // 清理过期的记录
    for (const [k, v] of requests.entries()) {
      if (now > v.resetTime) {
        requests.delete(k);
      }
    }

    // 检查当前请求
    const current = requests.get(key);
    if (current) {
      if (current.count >= maxRequests) {
        const resetIn = Math.ceil((current.resetTime - now) / 1000);
        return {
          continue: false,
          response: Response.json(
            {
              ok: false,
              error: '请求频率超限',
              details: {
                limit: maxRequests,
                windowMs,
                resetIn,
              },
            },
            {
              status: 429,
              headers: {
                'X-RateLimit-Limit': maxRequests.toString(),
                'X-RateLimit-Remaining': '0',
                'X-RateLimit-Reset': current.resetTime.toString(),
                'Retry-After': resetIn.toString(),
              },
            }
          ),
        };
      }
      current.count++;
    } else {
      requests.set(key, {
        count: 1,
        resetTime: now + windowMs,
      });
    }

    // 添加限流信息到响应头
    const result = await next();

    // 处理Response格式的结果
    if (result instanceof Response) {
      // WebSocket 升级响应（101）头部不可变，跳过
      if (result.status === 101) {
        return result;
      }

      const current = requests.get(key);
      if (current) {
        result.headers.set('X-RateLimit-Limit', maxRequests.toString());
        result.headers.set(
          'X-RateLimit-Remaining',
          Math.max(0, maxRequests - current.count).toString()
        );
        result.headers.set('X-RateLimit-Reset', current.resetTime.toString());
      }
      return result;
    }

    // 处理其他格式的结果
    const response = extractResponse(result);
    if (response) {
      // WebSocket 升级响应（101）头部不可变，跳过
      if (response.status === 101) {
        return result;
      }

      const current = requests.get(key);
      if (current) {
        response.headers.set('X-RateLimit-Limit', maxRequests.toString());
        response.headers.set(
          'X-RateLimit-Remaining',
          Math.max(0, maxRequests - current.count).toString()
        );
        response.headers.set('X-RateLimit-Reset', current.resetTime.toString());
      }
    }

    return result;
  };
}

/**
 * 获取客户端标识符
 */
function getClientIdentifier(context: MiddlewareContext): string {
  // 优先使用设备ID
  if (context.deviceId) {
    return `device:${context.deviceId}`;
  }

  // 使用IP地址
  const ip = context.headers['x-forwarded-for'] || context.headers['cf-connecting-ip'] || 'unknown';
  return `ip:${ip}`;
}
