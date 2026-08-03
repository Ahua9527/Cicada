/**
 * CicadaRelay Application
 * Main application class with middleware pipeline and routing
 */

import type { Env, MiddlewareContext } from '../types';
import { getLogger, type Logger } from '../infrastructure/logger';
import {
  MiddlewarePipeline,
  requestIdMiddleware,
  loggingMiddleware,
  securityHeadersMiddleware,
  corsMiddleware,
  rateLimitMiddleware,
  requestSizeLimitMiddleware,
} from '../infrastructure/middleware';
import { Router } from './router';
import { sanitizeRequestUrl } from './request-url-sanitizer';
import { API_CONSTANTS } from '../config/constants';
import {
  createPublicServerErrorResponse,
  enforcePublicServerErrorResponse,
  generateRequestId,
} from './public-error-response';

/**
 * CicadaRelay App
 */
export class CicadaRelayApp {
  private pipeline: MiddlewarePipeline;
  private logger: Logger;
  private router: Router;
  private env?: Env;

  constructor(env?: Env) {
    this.env = env;
    this.logger = getLogger({
      minLevel: 'info',
      enableConsole: true,
      enableStructured: true,
      env: env,
    });

    this.router = new Router();
    this.router.registerRoutes({
      handleRoot: this.handleRoot.bind(this),
      handleFavicon: this.handleFavicon.bind(this),
    });
    this.pipeline = this.createPipeline();
  }

  /**
   * Create middleware pipeline
   */
  private createPipeline(): MiddlewarePipeline {
    const enableCORS = this.env?.ENABLE_CORS === 'true';
    const enableRateLimit = this.env?.RATE_LIMIT_ENABLED !== 'false';

    const pipeline = new MiddlewarePipeline();

    // Basic middleware
    pipeline.use(requestIdMiddleware());
    pipeline.use(loggingMiddleware());
    pipeline.use(securityHeadersMiddleware());

    // Request body size limit
    pipeline.use(requestSizeLimitMiddleware({ maxSize: 10 * 1024 }));

    // CORS middleware
    if (enableCORS) {
      const allowedOrigins = this.env?.ALLOWED_ORIGINS
        ? this.env.ALLOWED_ORIGINS.split(',').map(origin => origin.trim())
        : ['http://localhost:3000', 'http://localhost:5173'];

      pipeline.use(
        corsMiddleware({
          allowedOrigins,
          allowedMethods: ['GET', 'POST', 'OPTIONS'],
          allowedHeaders: [
            'Content-Type',
            'Authorization',
            'mcp-session-id',
            'X-Request-ID',
            'X-Device-ID',
            'X-Agent-Identity-Public-Key',
            'X-Agent-Registration-Timestamp',
            'X-Agent-Registration-Nonce',
            'X-Agent-Registration-Signature',
          ],
          enabled: true,
        })
      );
    }

    // Rate limiting（限流键只使用可信来源，见 rate-limit.middleware）
    if (enableRateLimit) {
      pipeline.use(
        rateLimitMiddleware({
          windowMs: 60 * 1000,
          maxRequests: 100,
        })
      );
    }

    // Router middleware
    pipeline.use(this.router.createMiddleware());

    return pipeline;
  }

  /**
   * Handle request
   */
  // eslint-disable-next-line no-undef
  async handle(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const requestId = generateRequestId();

    const context: MiddlewareContext = {
      request,
      env,
      requestId,
      logger: this.logger,
      timestamp: Date.now(),
      url,
      method: request.method,
      headers: this.parseHeaders(request.headers),
      executionContext: ctx,
    };

    try {
      const pipelineResponse = await this.pipeline.execute(context);
      const response = enforcePublicServerErrorResponse(pipelineResponse, context.requestId);

      return response;
    } catch (error) {
      this.logger.error('Request handling failed', {
        requestId: context.requestId,
        error: error as Error,
        context: {
          route: url.pathname.startsWith('/relay/') ? '/relay/:liveSession' : url.pathname,
          error_type: error instanceof Error ? error.name : 'UnknownError',
          duration_ms: Date.now() - context.timestamp,
          ...(request.headers.get('Upgrade')?.toLowerCase() === 'websocket'
            ? { websocket_outcome: 'upgrade_failed' }
            : {}),
        },
        tags: ['request', 'error'],
      });

      return createPublicServerErrorResponse(context.requestId);
    }
  }

  private async handleRoot(_context: MiddlewareContext): Promise<Response> {
    return Response.json({
      ok: true,
      message: 'CicadaRelay API Server',
      version: API_CONSTANTS.VERSION,
      status: 'running',
      endpoints: {
        agent_websocket: '/relay/:liveSession',
        shortcuts_command: '/v1/shortcuts/command',
        status: '/status',
        devices: '/devices',
        health: '/health',
      },
      timestamp: Date.now(),
    });
  }

  private async handleFavicon(_context: MiddlewareContext): Promise<Response> {
    return new Response(null, { status: 204 });
  }

  private parseHeaders(headers: Headers): Record<string, string> {
    const result: Record<string, string> = {};
    headers.forEach((value, key) => {
      result[key.toLowerCase()] = value;
    });
    return result;
  }

  private sanitizeUrl(rawUrl: string): string {
    return sanitizeRequestUrl(rawUrl);
  }
}
