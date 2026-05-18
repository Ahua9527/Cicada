/**
 * CORS中间件
 */

import type { Middleware, MiddlewareResult } from './types';
import { extractResponse } from './types';

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

    // WebSocket 升级响应（101）头部不可变，直接返回
    if (response.status === 101) {
      return result;
    }

    const corsHeaders = getCorsHeaders(
      context.request.headers.get('Origin') ?? '',
      allowedOrigins,
      allowedMethods,
      allowedHeaders,
      maxAge
    );

    return addCorsHeaders(result, corsHeaders);
  };
}

/**
 * 获取CORS响应头
 */
function getCorsHeaders(
  origin: string,
  allowedOrigins: string[],
  allowedMethods: string[],
  allowedHeaders: string[],
  maxAge: number
): Record<string, string> {
  const headers: Record<string, string> = {};

  // 检查是否允许该源
  if (
    allowedOrigins.length === 0 ||
    allowedOrigins.includes('*') ||
    allowedOrigins.includes(origin)
  ) {
    headers['Access-Control-Allow-Origin'] = allowedOrigins.includes('*') ? '*' : origin;
    headers['Access-Control-Allow-Methods'] = allowedMethods.join(', ');
    headers['Access-Control-Allow-Headers'] = allowedHeaders.join(', ');
    headers['Access-Control-Max-Age'] = maxAge.toString();
  }

  return headers;
}

/**
 * 添加CORS头到响应
 */
function addCorsHeaders(
  result: MiddlewareResult,
  headers: Record<string, string>
): MiddlewareResult {
  if (result instanceof Response) {
    const newHeaders = new Headers(result.headers);
    Object.entries(headers).forEach(([key, value]) => {
      newHeaders.set(key, value);
    });

    return new Response(result.body, {
      status: result.status,
      statusText: result.statusText,
      headers: newHeaders,
    });
  }

  return result;
}
