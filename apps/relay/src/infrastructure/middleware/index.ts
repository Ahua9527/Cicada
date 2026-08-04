/**
 * 中间件系统导出
 */

export * from './types';
export * from './pipeline';
export * from './logging.middleware';
export * from './cors.middleware';
export * from './security.middleware';
export * from './rate-limit.middleware';

import { MiddlewarePipeline } from './pipeline';
import { requestIdMiddleware, loggingMiddleware } from './logging.middleware';
import { corsMiddleware, type CorsOptions } from './cors.middleware';
import { securityHeadersMiddleware, requestSizeLimitMiddleware } from './security.middleware';
import { rateLimitMiddleware, type RateLimitOptions } from './rate-limit.middleware';

/**
 * 创建默认中间件管道的选项
 */
export interface DefaultPipelineOptions {
  enableCORS?: boolean;
  enableRateLimit?: boolean;
  corsOptions?: CorsOptions;
  rateLimitOptions?: RateLimitOptions;
  maxRequestSize?: number;
}

/**
 * 创建默认中间件管道
 */
export function createDefaultPipeline(options: DefaultPipelineOptions = {}): MiddlewarePipeline {
  const {
    enableCORS = false,
    enableRateLimit = true,
    corsOptions,
    rateLimitOptions = {
      windowMs: 60 * 1000, // 1分钟
      maxRequests: 100,
    },
    maxRequestSize = 10 * 1024, // 10KB
  } = options;

  const pipeline = new MiddlewarePipeline();

  // 基础中间件
  pipeline.use(requestIdMiddleware());
  pipeline.use(loggingMiddleware());
  pipeline.use(securityHeadersMiddleware());
  pipeline.use(requestSizeLimitMiddleware({ maxSize: maxRequestSize }));

  // CORS中间件
  if (enableCORS) {
    pipeline.use(corsMiddleware(corsOptions));
  }

  // 限流中间件（限流键只使用可信来源，见 rate-limit.middleware）
  if (enableRateLimit) {
    pipeline.use(rateLimitMiddleware(rateLimitOptions));
  }

  return pipeline;
}
