/**
 * Router
 * Route matching and dispatching logic
 */

import type { MiddlewareContext } from '../types';
import {
  handleWebSocketRoute,
  handleStatusRoute,
  handleDeviceListRoute,
  handleHealthRoute,
  handleShortcutCommandRoute,
} from './routes';

export interface Route {
  pattern: RegExp;
  methods: string[];
  handler: (context: MiddlewareContext) => Promise<Response>;
}

/**
 * Router class
 */
export class Router {
  private routes: Route[] = [];

  /**
   * Register routes
   */
  registerRoutes(additionalHandlers: {
    handleRoot: (context: MiddlewareContext) => Promise<Response>;
    handleFavicon: (context: MiddlewareContext) => Promise<Response>;
  }) {
    this.routes = [
      { pattern: /^\/$/, methods: ['GET'], handler: additionalHandlers.handleRoot },
      { pattern: /^\/favicon\.ico$/, methods: ['GET'], handler: additionalHandlers.handleFavicon },
      { pattern: /^\/relay\/[^/]+$/, methods: ['GET'], handler: handleWebSocketRoute },
      { pattern: /^\/v1\/shortcuts\/command$/, methods: ['POST'], handler: handleShortcutCommandRoute },
      { pattern: /^\/status$/, methods: ['GET'], handler: handleStatusRoute },
      { pattern: /^\/devices$/, methods: ['GET'], handler: handleDeviceListRoute },
      { pattern: /^\/health$/, methods: ['GET'], handler: handleHealthRoute },
    ];
  }

  /**
   * Find matching route
   */
  findRoute(pathname: string, method: string): Route | undefined {
    return this.routes.find(
      route => route.pattern.test(pathname) && route.methods.includes(method)
    );
  }

  /**
   * Create router middleware
   */
  createMiddleware() {
    return async (context: MiddlewareContext, _next: () => Promise<any>) => {
      const { request } = context;
      const url = new URL(request.url);
      const { pathname, method } = { pathname: url.pathname, method: request.method };

      const route = this.findRoute(pathname, method);

      if (!route) {
        context.logger.warn('Route not found', {
          requestId: context.requestId,
          context: { pathname, method },
          tags: ['routing', 'error'],
        });

        return {
          continue: false,
          response: Response.json(
            {
              ok: false,
              error: 'API endpoint not found',
              path: pathname,
            },
            { status: 404 }
          ),
        };
      }

      try {
        const response = await route.handler(context);
        return { continue: false, response };
      } catch (error) {
        context.logger.error('Route handler failed', {
          requestId: context.requestId,
          error: error as Error,
          context: { pathname, method },
          tags: ['routing', 'error'],
        });

        return {
          continue: false,
          response: Response.json(
            {
              ok: false,
              error: 'Route handler failed',
              message: error instanceof Error ? error.message : 'Unknown error',
              request_id: context.requestId,
            },
            { status: 500 }
          ),
        };
      }
    };
  }
}
