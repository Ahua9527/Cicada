/**
 * 中间件管道
 */

import type { MiddlewareContext, Middleware, MiddlewareResult } from './types';
import { extractResponse } from './types';
import { createPublicServerErrorResponse } from '../../presentation/public-error-response';

/**
 * 中间件管道类
 */
export class MiddlewarePipeline {
  private middlewares: Middleware[] = [];

  /**
   * 添加中间件到管道
   */
  use(middleware: Middleware): this {
    this.middlewares.push(middleware);
    return this;
  }

  /**
   * 执行中间件管道
   */
  async execute(context: MiddlewareContext): Promise<Response> {
    let index = 0;

    const next = async (): Promise<MiddlewareResult> => {
      if (index >= this.middlewares.length) {
        return { continue: true };
      }

      const middleware = this.middlewares[index++];
      return await middleware(context, next);
    };

    try {
      const result = await next();

      const response = extractResponse(result);
      if (response) {
        // 如果是 WebSocket 升级响应（101），不再执行后续中间件
        // 因为 WebSocket 响应的头是不可变的，后续中间件尝试修改会导致错误
        if (response.status === 101) {
          return response;
        }
        return response;
      }

      // 如果所有中间件都执行完成但没有返回响应，返回404
      return new Response(
        JSON.stringify({
          ok: false,
          error: 'API endpoint not found',
          path: context.url.pathname,
        }),
        {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        }
      );
    } catch (error) {
      // WebSocket 升级后的错误通常表示连接已成功建立
      // 记录警告但不返回错误响应（可能连接已经升级）
      if (context.url.pathname.startsWith('/relay/')) {
        context.logger.warn('WebSocket pipeline error (connection may be established)', {
          requestId: context.requestId,
          error: error as Error,
          tags: ['websocket', 'error', 'ignored'],
        });
        return createPublicServerErrorResponse(context.requestId);
      }

      context.logger.error('Pipeline error occurred', {
        requestId: context.requestId,
        error: error as Error,
        tags: ['middleware', 'error'],
      });

      return createPublicServerErrorResponse(context.requestId);
    }
  }
}
