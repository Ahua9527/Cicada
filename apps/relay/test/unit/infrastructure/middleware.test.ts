/**
 * 中间件单元测试
 */

import {
  MiddlewarePipeline,
  requestIdMiddleware,
  corsMiddleware,
  securityHeadersMiddleware,
  requestSizeLimitMiddleware,
  createDefaultPipeline,
} from '../../../src/infrastructure/middleware';
import { MiddlewareContext } from '../../../src/infrastructure/middleware/types';
import { Logger } from '../../../src/infrastructure/logger';

describe('Middleware', () => {
  describe('MiddlewarePipeline', () => {
    it('should execute middleware in order', async () => {
      const pipeline = new MiddlewarePipeline();
      const execution: string[] = [];

      pipeline.use(async (_ctx, next) => {
        execution.push('first');
        return next();
      });

      pipeline.use(async (_ctx, next) => {
        execution.push('second');
        return next();
      });

      const request = new Request('http://localhost/test');
      const logger = new Logger({ enableConsole: false });
      const url = new URL('http://localhost/test');
      const ctx: MiddlewareContext = {
        request,
        env: {} as any,
        requestId: 'test-id',
        logger,
        timestamp: Date.now(),
        url,
        method: 'GET',
        headers: {},
      };

      const response = await pipeline.execute(ctx);

      expect(execution).toEqual(['first', 'second']);
      expect(response).toBeInstanceOf(Response);
    });

    it('should stop execution when middleware returns response', async () => {
      const pipeline = new MiddlewarePipeline();
      const execution: string[] = [];

      pipeline.use(async (_ctx, _next) => {
        execution.push('first');
        return {
          continue: false,
          response: new Response('stopped'),
        };
      });

      pipeline.use(async (_ctx, next) => {
        execution.push('second');
        return next();
      });

      const request = new Request('http://localhost/test');
      const logger = new Logger({ enableConsole: false });
      const url = new URL('http://localhost/test');
      const ctx: MiddlewareContext = {
        request,
        env: {} as any,
        requestId: 'test-id',
        logger,
        timestamp: Date.now(),
        url,
        method: 'GET',
        headers: {},
      };

      const response = await pipeline.execute(ctx);

      expect(execution).toEqual(['first']);
      expect(response).toBeInstanceOf(Response);
      expect(await response.text()).toBe('stopped');
    });
  });

  describe('requestIdMiddleware', () => {
    it('should add requestId to context', async () => {
      const middleware = requestIdMiddleware();
      const request = new Request('http://localhost/test');
      const logger = new Logger({ enableConsole: false });
      const url = new URL('http://localhost/test');
      let capturedId = '';

      const ctx: MiddlewareContext = {
        request,
        env: {} as any,
        requestId: '',
        logger,
        timestamp: Date.now(),
        url,
        method: 'GET',
        headers: {},
      };

      const result = await middleware(ctx, async () => {
        capturedId = ctx.requestId;
        return { continue: true };
      });

      expect(capturedId).toBeTruthy();
      expect(capturedId.startsWith('req_')).toBe(true);
      expect((result as any).continue).toBe(true);
    });

    it('should redact Bark secrets from request start logs', async () => {
      const middleware = requestIdMiddleware();
      const request = new Request(
        'http://localhost/bark/devicekey/Front%20Door/Motion?devicetoken=abc123&group=sentry'
      );
      const logger = new Logger({ enableConsole: false });
      const url = new URL(request.url);

      const ctx: MiddlewareContext = {
        request,
        env: {} as any,
        requestId: '',
        logger,
        timestamp: Date.now(),
        url,
        method: 'GET',
        headers: {},
      };

      await middleware(ctx, async () => ({ continue: true }));

      const [entry] = logger.getRecentLogs(1);
      expect(entry.message).toBe('Request started: GET /bark/[device_key]/[payload]');
      expect(entry.context?.url).toBe(
        'http://localhost/bark/[device_key]/[payload]?devicetoken=%5BFILTERED%5D&group=%5BFILTERED%5D'
      );
    });

    it('should redact legacy /bark request start logs when Bark uses a custom root', async () => {
      const middleware = requestIdMiddleware();
      const request = new Request(
        'http://localhost/bark/devicekey/Front%20Door/Motion?devicetoken=abc123&group=sentry'
      );
      const logger = new Logger({ enableConsole: false });
      const url = new URL(request.url);

      const ctx: MiddlewareContext = {
        request,
        env: { BARK_ROOT_PATH: '/push' } as any,
        requestId: '',
        logger,
        timestamp: Date.now(),
        url,
        method: 'GET',
        headers: {},
      };

      await middleware(ctx, async () => ({ continue: true }));

      const [entry] = logger.getRecentLogs(1);
      expect(entry.message).toBe('Request started: GET /bark/[device_key]/[payload]');
      expect(entry.context?.url).not.toContain('devicekey');
      expect(entry.context?.url).not.toContain('abc123');
    });
  });

  describe('securityHeadersMiddleware', () => {
    it('should call next middleware', async () => {
      const middleware = securityHeadersMiddleware();
      const request = new Request('http://localhost/test');
      const logger = new Logger({ enableConsole: false });
      const url = new URL('http://localhost/test');

      const ctx: MiddlewareContext = {
        request,
        env: {} as any,
        requestId: 'test-id',
        logger,
        timestamp: Date.now(),
        url,
        method: 'GET',
        headers: {},
      };

      let nextCalled = false;
      const result = await middleware(ctx, async () => {
        nextCalled = true;
        return {
          continue: false,
          response: new Response('test'),
        };
      });

      expect(nextCalled).toBe(true);
      expect((result as any).response).toBeDefined();
    });
  });

  describe('requestSizeLimitMiddleware', () => {
    it('should redact Bark paths when request size logs are emitted', async () => {
      const middleware = requestSizeLimitMiddleware({ maxSize: 4 });
      const request = new Request(
        'http://localhost/bark/devicekey/Front%20Door/Motion?devicetoken=abc123',
        {
          method: 'POST',
          headers: { 'content-length': '8' },
          body: 'oversize',
        }
      );
      const logger = new Logger({ enableConsole: false });
      const url = new URL(request.url);

      const ctx: MiddlewareContext = {
        request,
        env: {} as any,
        requestId: 'test-id',
        logger,
        timestamp: Date.now(),
        url,
        method: 'POST',
        headers: {},
      };

      const result = await middleware(ctx, async () => ({ continue: true }));
      const [entry] = logger.getRecentLogs(1);

      expect((result as any).response.status).toBe(413);
      expect(entry.context?.path).toBe('/bark/[device_key]/[payload]');
    });
  });

  describe('corsMiddleware', () => {
    it('should be created with allowed origins', () => {
      const middleware = corsMiddleware({ allowedOrigins: ['https://example.com'] });
      expect(middleware).toBeDefined();
      expect(typeof middleware).toBe('function');
    });

    it('should process requests', async () => {
      const middleware = corsMiddleware({ allowedOrigins: ['*'] });
      const request = new Request('http://localhost/test', {
        method: 'GET',
        headers: { Origin: 'https://example.com' },
      });
      const logger = new Logger({ enableConsole: false });
      const url = new URL('http://localhost/test');

      const ctx: MiddlewareContext = {
        request,
        env: {} as any,
        requestId: 'test-id',
        logger,
        timestamp: Date.now(),
        url,
        method: 'GET',
        headers: {},
      };

      let nextCalled = false;
      const result = await middleware(ctx, async () => {
        nextCalled = true;
        return { continue: true };
      });

      expect(nextCalled).toBe(true);
      expect(result).toHaveProperty('continue');
    });
  });

  describe('createDefaultPipeline', () => {
    it('should create pipeline with default middleware', () => {
      const pipeline = createDefaultPipeline();
      expect(pipeline).toBeInstanceOf(MiddlewarePipeline);
    });

    it('should include CORS middleware when enabled', () => {
      const pipeline = createDefaultPipeline({ enableCORS: true });
      expect(pipeline).toBeInstanceOf(MiddlewarePipeline);
    });

    it('should include rate limiting when enabled', () => {
      const pipeline = createDefaultPipeline({ enableRateLimit: true });
      expect(pipeline).toBeInstanceOf(MiddlewarePipeline);
    });
  });
});
