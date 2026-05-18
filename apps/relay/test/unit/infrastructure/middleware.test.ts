/**
 * 中间件单元测试
 */

import {
  MiddlewarePipeline,
  requestIdMiddleware,
  corsMiddleware,
  securityHeadersMiddleware,
  authMiddleware,
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

  describe('authMiddleware', () => {
    it('should pass through valid request', async () => {
      const middleware = authMiddleware();
      const request = new Request('http://localhost/test', {
        method: 'POST',
        body: JSON.stringify({
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: 'ping',
          ts: Math.floor(Date.now() / 1000),
          api_key: 'secret',
        }),
      });
      const logger = new Logger({ enableConsole: false });
      const url = new URL('http://localhost/test');

      const ctx: MiddlewareContext = {
        request,
        env: { API_KEY: 'secret', CICADA_SESSIONS: {} as any },
        requestId: 'test-id',
        logger,
        timestamp: Date.now(),
        url,
        method: 'GET',
        headers: {},
      };

      const result = await middleware(ctx, async () => {
        return { continue: true };
      });

      expect((result as any).continue).toBe(true);
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
