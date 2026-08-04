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

interface RateLimitEntry {
  count: number;
  resetTime: number;
}

const CLEANUP_INTERVAL_MS = 60_000;
const CLEANUP_SIZE_THRESHOLD = 1_000;
const CLEANUP_BATCH_SIZE = 100;

/**
 * 限流中间件
 */
export function rateLimitMiddleware(options: RateLimitOptions): Middleware {
  const { windowMs, maxRequests, keyGenerator } = options;
  const requests = new Map<string, RateLimitEntry>();
  let lastCleanupAt = Date.now();
  let cleanupCursor: IterableIterator<[string, RateLimitEntry]> | undefined;

  const cleanupExpiredEntries = (now: number): void => {
    cleanupCursor ??= requests.entries();

    for (let scanned = 0; scanned < CLEANUP_BATCH_SIZE; scanned++) {
      const nextEntry = cleanupCursor.next();
      if (nextEntry.done) {
        cleanupCursor = undefined;
        lastCleanupAt = now;
        return;
      }

      const [entryKey, entry] = nextEntry.value;
      if (now > entry.resetTime) {
        requests.delete(entryKey);
      }
    }
  };

  return async (context, next) => {
    const key = keyGenerator ? keyGenerator(context) : getClientIdentifier(context);
    const now = Date.now();

    // 当前 key 始终惰性过期，避免旧窗口错误限流。
    const existing = requests.get(key);
    if (existing && now > existing.resetTime) {
      requests.delete(key);
    }

    // 全局清理按批次推进，单个请求最多扫描固定数量的记录。
    if (
      cleanupCursor !== undefined ||
      now - lastCleanupAt >= CLEANUP_INTERVAL_MS ||
      requests.size > CLEANUP_SIZE_THRESHOLD
    ) {
      cleanupExpiredEntries(now);
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
 *
 * 限流键只使用可信来源：Cloudflare 边缘注入的 cf-connecting-ip（客户端
 * 无法伪造）；x-forwarded-for 仅在 cf-connecting-ip 缺失时作为兜底（不可信
 * 但仍优于 'unknown'，可避免同源 IP 共用 unknown 桶）。若都缺失才退化到
 * 'unknown'。不使用 x-device-id 等客户端自报身份——其在 DO 内完成签名校验
 * 前不可信，否则攻击者可轮换标识获取新限流桶或消耗受害设备配额。
 */
function getClientIdentifier(context: MiddlewareContext): string {
  // 优先使用 Cloudflare 边缘注入的 cf-connecting-ip
  const cfIp =
    context.headers['cf-connecting-ip'] ??
    (context.request.cf as { clientIp?: string } | undefined)?.clientIp;
  if (cfIp) {
    return `ip:${cfIp}`;
  }

  // 兜底：x-forwarded-for（不可信，但优于 unknown）
  const forwarded = context.headers['x-forwarded-for'];
  if (forwarded) {
    return `ip:${forwarded}`;
  }

  return 'ip:unknown';
}
