/**
 * CORS中间件
 */

import type { Middleware, MiddlewareResult } from './types';
import { extractResponse, isControlResult, isWebSocketUpgradeResponse } from './types';

export interface CorsOptions {
  allowedOrigins?: string[];
  allowedMethods?: string[];
  allowedHeaders?: string[];
  maxAge?: number;
  enabled?: boolean;
}

/**
 * CORS中间件
 */
export function corsMiddleware(options: CorsOptions = {}): Middleware {
  const {
    allowedOrigins = [],
    allowedMethods = ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders = ['Content-Type', 'Authorization', 'X-Request-ID'],
    maxAge = 86400,
    enabled = true,
  } = options;

  return async (context, next) => {
    if (!enabled) {
      return next();
    }

    // 如果是OPTIONS请求，直接返回预检响应
    if (context.method === 'OPTIONS') {
      const corsHeaders = getCorsHeaders(
        context.request.headers.get('Origin') ?? '',
        allowedOrigins,
        allowedMethods,
        allowedHeaders,
        maxAge
      );
      return new Response(null, {
        status: 200,
        headers: corsHeaders,
      });
    }

    const result = await next();

    const response = extractResponse(result);
    if (!response) {
      return result;
    }

    // WebSocket 升级响应头部不可变，直接返回
    if (isWebSocketUpgradeResponse(response)) {
      return result;
    }

    const corsHeaders = getCorsHeaders(
      context.request.headers.get('Origin') ?? '',
      allowedOrigins,
      allowedMethods,
      allowedHeaders,
      maxAge
    );

    return addCorsHeaders(result, response, corsHeaders);
  };
}

/**
 * 获取CORS响应头
 *
 * M12: allowedOrigins 为空时默认拒绝（不返回 CORS 头），只有显式配置
 * allowedOrigins（含 '*'）才放行。这是更安全的默认值。
 */
function getCorsHeaders(
  origin: string,
  allowedOrigins: string[],
  allowedMethods: string[],
  allowedHeaders: string[],
  maxAge: number
): Record<string, string> {
  const headers: Record<string, string> = {};

  if (allowedOrigins.length === 0) {
    return headers;
  }

  // 检查是否允许该源
  if (allowedOrigins.includes('*') || allowedOrigins.includes(origin)) {
    headers['Access-Control-Allow-Origin'] = allowedOrigins.includes('*') ? '*' : origin;
    headers['Access-Control-Allow-Methods'] = allowedMethods.join(', ');
    headers['Access-Control-Allow-Headers'] = allowedHeaders.join(', ');
    headers['Access-Control-Max-Age'] = maxAge.toString();
  }

  return headers;
}

/**
 * 添加CORS头到响应。路由返回的是 { continue: false, response } 包装，
 * 不是裸 Response，两种形式都要加头并保持原来的形式返回。
 */
function addCorsHeaders(
  result: MiddlewareResult,
  response: Response,
  headers: Record<string, string>
): MiddlewareResult {
  const newHeaders = new Headers(response.headers);
  Object.entries(headers).forEach(([key, value]) => {
    newHeaders.set(key, value);
  });

  const decorated = new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: newHeaders,
  });
  return isControlResult(result) ? { ...result, response: decorated } : decorated;
}
