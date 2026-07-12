/**
 * 中间件单元测试
 */

import {
  MiddlewarePipeline,
  requestIdMiddleware,
  loggingMiddleware,
  corsMiddleware,
  rateLimitMiddleware,
  securityHeadersMiddleware,
  createDefaultPipeline,
} from '../../../src/infrastructure/middleware';
import type {
  MiddlewareContext,
  MiddlewareResult,
} from '../../../src/infrastructure/middleware/types';
import { Logger } from '../../../src/infrastructure/logger';

function createContext(overrides: Partial<MiddlewareContext> = {}): MiddlewareContext {
  const request = overrides.request ?? new Request('http://localhost/test');
  return {
    request,
    env: {} as MiddlewareContext['env'],
    requestId: 'test-id',
    logger: new Logger({ enableConsole: false }),
    timestamp: Date.now(),
    url: new URL(request.url),
    method: request.method,
    headers: Object.fromEntries(request.headers.entries()),
    ...overrides,
  };
}

function createUpgradeResponse(): Response {
  const response = Object.create(Response.prototype) as Response;
  Object.defineProperty(response, 'status', { value: 101 });
  return response;
}

describe('Middleware', () => {
  describe('MiddlewarePipeline', () => {
    it('executes middleware in order and returns 404 when no response exists', async () => {
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

      const response = await pipeline.execute(createContext());

      expect(execution).toEqual(['first', 'second']);
      expect(response.status).toBe(404);
      await expect(response.json()).resolves.toMatchObject({
        ok: false,
        path: '/test',
      });
    });

    it('stops execution when middleware returns a response', async () => {
      const pipeline = new MiddlewarePipeline();
      const execution: string[] = [];

      pipeline.use(async () => {
        execution.push('first');
        return { continue: false, response: new Response('stopped') };
      });
      pipeline.use(async (_ctx, next) => {
        execution.push('second');
        return next();
      });

      const response = await pipeline.execute(createContext());

      expect(execution).toEqual(['first']);
      await expect(response.text()).resolves.toBe('stopped');
    });

    it('returns an upgrade response unchanged', async () => {
      const upgrade = createUpgradeResponse();
      const pipeline = new MiddlewarePipeline().use(async () => upgrade);

      await expect(pipeline.execute(createContext())).resolves.toBe(upgrade);
    });

    it.each(['/api/test', '/relay/device-1'])(
      'sanitizes errors raised for %s',
      async pathname => {
        const logger = new Logger({ enableConsole: false });
        const logSpy = jest.spyOn(logger, pathname.startsWith('/relay/') ? 'warn' : 'error');
        const pipeline = new MiddlewarePipeline().use(async () => {
          throw new Error('secret=/private/path');
        });

        const response = await pipeline.execute(
          createContext({
            requestId: 'req-error',
            logger,
            url: new URL(`http://localhost${pathname}`),
          })
        );

        expect(response.status).toBe(500);
        await expect(response.json()).resolves.toEqual({
          ok: false,
          error: 'Internal server error',
          request_id: 'req-error',
        });
        expect(logSpy).toHaveBeenCalledWith(
          expect.any(String),
          expect.objectContaining({ requestId: 'req-error' })
        );
      }
    );
  });

  describe('requestIdMiddleware', () => {
    it('preserves an existing request ID', async () => {
      const logger = new Logger({ enableConsole: false });
      const infoSpy = jest.spyOn(logger, 'info');
      const context = createContext({
        logger,
        headers: { 'x-request-id': 'caller-id' },
        url: new URL('https://example.com/test?token=secret'),
      });

      await requestIdMiddleware()(context, async () => ({ continue: true }));

      expect(context.requestId).toBe('caller-id');
      expect(infoSpy).toHaveBeenCalledWith(
        'Request started: GET /test',
        expect.objectContaining({ requestId: 'caller-id' })
      );
      expect(JSON.stringify(infoSpy.mock.calls)).not.toContain('secret');
    });

    it('generates a request ID when the header is absent', async () => {
      const context = createContext({ requestId: '' });
      const result = await requestIdMiddleware()(context, async () => ({ continue: true }));

      expect(context.requestId).toMatch(/^req_/);
      expect(result).toEqual({ continue: true });
    });
  });

  describe('loggingMiddleware', () => {
    it.each([
      [200, 'info', 'Request completed: 200'],
      [404, 'warn', 'Request failed: 404'],
    ] as const)('logs status %i at %s level', async (status, level, message) => {
      const logger = new Logger({ enableConsole: false });
      const spy = jest.spyOn(logger, level);
      const response = new Response(null, { status });

      const result = await loggingMiddleware()(createContext({ logger }), async () => response);

      expect(result).toBe(response);
      expect(spy).toHaveBeenCalledWith(message, expect.objectContaining({ requestId: 'test-id' }));
    });

    it('logs successful WebSocket upgrades', async () => {
      const logger = new Logger({ enableConsole: false });
      const infoSpy = jest.spyOn(logger, 'info');
      const upgrade = createUpgradeResponse();

      await loggingMiddleware()(createContext({ logger }), async () => upgrade);

      expect(infoSpy).toHaveBeenCalledWith(
        'WebSocket upgrade completed',
        expect.objectContaining({ requestId: 'test-id' })
      );
    });

    it('warns when a stopped control result has no response', async () => {
      const logger = new Logger({ enableConsole: false });
      const warnSpy = jest.spyOn(logger, 'warn');

      await loggingMiddleware()(createContext({ logger }), async () => ({ continue: false }));

      expect(warnSpy).toHaveBeenCalledWith(
        'Request completed with no response',
        expect.objectContaining({ requestId: 'test-id' })
      );
    });

    it('does not log a continuing control result as completed', async () => {
      const logger = new Logger({ enableConsole: false });
      const warnSpy = jest.spyOn(logger, 'warn');
      const infoSpy = jest.spyOn(logger, 'info');

      await loggingMiddleware()(createContext({ logger }), async () => ({ continue: true }));

      expect(warnSpy).not.toHaveBeenCalled();
      expect(infoSpy).not.toHaveBeenCalled();
    });
  });

  describe('securityHeadersMiddleware', () => {
    it('calls the next middleware', async () => {
      const response = new Response('test');
      const result = await securityHeadersMiddleware()(createContext(), async () => ({
        continue: false,
        response,
      }));

      expect((result as { response: Response }).response).toBe(response);
    });
  });

  describe('corsMiddleware', () => {
    it('bypasses processing when disabled', async () => {
      const next = jest.fn<Promise<MiddlewareResult>, []>().mockResolvedValue({ continue: true });
      const result = await corsMiddleware({ enabled: false })(createContext(), next);

      expect(result).toEqual({ continue: true });
      expect(next).toHaveBeenCalledTimes(1);
    });

    it('answers preflight with configured headers', async () => {
      const request = new Request('http://localhost/test', {
        method: 'OPTIONS',
        headers: { Origin: 'https://allowed.example' },
      });
      const next = jest.fn();

      const result = (await corsMiddleware({
        allowedOrigins: ['https://allowed.example'],
        allowedMethods: ['GET'],
        allowedHeaders: ['X-Test'],
        maxAge: 60,
      })(createContext({ request, method: 'OPTIONS' }), next)) as Response;

      expect(next).not.toHaveBeenCalled();
      expect(result.status).toBe(200);
      expect(result.headers.get('Access-Control-Allow-Origin')).toBe('https://allowed.example');
      expect(result.headers.get('Access-Control-Allow-Methods')).toBe('GET');
      expect(result.headers.get('Access-Control-Allow-Headers')).toBe('X-Test');
      expect(result.headers.get('Access-Control-Max-Age')).toBe('60');
    });

    it.each([
      [[], 'https://caller.example'],
      [['*'], '*'],
      [['https://caller.example'], 'https://caller.example'],
    ])('adds allowed origin headers for %j', async (allowedOrigins, expectedOrigin) => {
      const request = new Request('http://localhost/test', {
        headers: { Origin: 'https://caller.example' },
      });
      const response = new Response('ok');

      const result = (await corsMiddleware({ allowedOrigins })(
        createContext({ request }),
        async () => response
      )) as Response;

      expect(result).not.toBe(response);
      expect(result.headers.get('Access-Control-Allow-Origin')).toBe(expectedOrigin);
    });

    it('does not add headers for a rejected origin', async () => {
      const request = new Request('http://localhost/test', {
        headers: { Origin: 'https://rejected.example' },
      });

      const result = (await corsMiddleware({ allowedOrigins: ['https://allowed.example'] })(
        createContext({ request }),
        async () => new Response('ok')
      )) as Response;

      expect(result.headers.has('Access-Control-Allow-Origin')).toBe(false);
    });

    it('preserves control results and upgrade responses', async () => {
      const control = { continue: true };
      const middleware = corsMiddleware({ allowedOrigins: ['*'] });
      await expect(middleware(createContext(), async () => control)).resolves.toBe(control);

      const upgrade = createUpgradeResponse();
      await expect(middleware(createContext(), async () => upgrade)).resolves.toBe(upgrade);
    });
  });

  describe('rateLimitMiddleware', () => {
    afterEach(() => {
      jest.useRealTimers();
      jest.restoreAllMocks();
    });

    it('adds headers and returns the existing response', async () => {
      const response = new Response('ok');
      const middleware = rateLimitMiddleware({ windowMs: 1_000, maxRequests: 2 });

      const result = await middleware(createContext({ deviceId: 'device-1' }), async () => response);

      expect(result).toBe(response);
      expect(response.headers.get('X-RateLimit-Limit')).toBe('2');
      expect(response.headers.get('X-RateLimit-Remaining')).toBe('1');
    });

    it('uses a custom key and preserves control response shape', async () => {
      const response = new Response('ok');
      const keyGenerator = jest.fn(() => 'custom');
      const middleware = rateLimitMiddleware({ windowMs: 1_000, maxRequests: 2, keyGenerator });
      const result = await middleware(createContext(), async () => ({
        continue: false,
        response,
      }));

      expect(keyGenerator).toHaveBeenCalled();
      expect(result).toEqual({ continue: false, response });
      expect(response.headers.get('X-RateLimit-Remaining')).toBe('1');
    });

    it('falls back through forwarding headers and unknown clients', async () => {
      const middleware = rateLimitMiddleware({ windowMs: 1_000, maxRequests: 1 });

      await middleware(createContext({ headers: { 'x-forwarded-for': '192.0.2.1' } }), async () =>
        new Response('ok')
      );
      await middleware(createContext({ headers: { 'cf-connecting-ip': '192.0.2.2' } }), async () =>
        new Response('ok')
      );
      await expect(
        middleware(createContext({ headers: {} }), async () => new Response('ok'))
      ).resolves.toBeInstanceOf(Response);
    });

    it('returns the existing 429 contract at the limit', async () => {
      const middleware = rateLimitMiddleware({ windowMs: 10_000, maxRequests: 1 });
      const context = createContext({ deviceId: 'limited' });
      await middleware(context, async () => new Response('ok'));

      const result = (await middleware(context, async () => new Response('unexpected'))) as {
        continue: false;
        response: Response;
      };

      expect(result.continue).toBe(false);
      expect(result.response.status).toBe(429);
      expect(result.response.headers.get('Retry-After')).toBe('10');
      expect(result.response.headers.get('X-RateLimit-Remaining')).toBe('0');
      await expect(result.response.json()).resolves.toMatchObject({
        ok: false,
        error: '请求频率超限',
        details: { limit: 1, windowMs: 10_000, resetIn: 10 },
      });
    });

    it('resets an expired key and preserves upgrade responses', async () => {
      jest.useFakeTimers();
      jest.setSystemTime(1_000);
      const middleware = rateLimitMiddleware({ windowMs: 100, maxRequests: 1 });
      const context = createContext({ deviceId: 'expiring' });
      await middleware(context, async () => new Response('ok'));
      jest.setSystemTime(1_101);

      await expect(middleware(context, async () => new Response('fresh'))).resolves.toBeInstanceOf(
        Response
      );

      const upgrade = createUpgradeResponse();
      await expect(
        rateLimitMiddleware({ windowMs: 100, maxRequests: 1 })(createContext(), async () => upgrade)
      ).resolves.toBe(upgrade);
    });

    it('waits for the cleanup interval when the store remains small', async () => {
      jest.useFakeTimers();
      jest.setSystemTime(1_000);

      const entriesSpy = jest.spyOn(Map.prototype, 'entries');
      const middleware = rateLimitMiddleware({
        windowMs: 120_000,
        maxRequests: 2,
        keyGenerator: context => context.deviceId ?? 'unknown',
      });

      await middleware(createContext({ deviceId: 'one' }), async () => new Response('ok'));
      jest.setSystemTime(60_999);
      await middleware(createContext({ deviceId: 'two' }), async () => new Response('ok'));

      expect(entriesSpy).not.toHaveBeenCalled();

      jest.setSystemTime(61_000);
      await middleware(createContext({ deviceId: 'three' }), async () => new Response('ok'));
      expect(entriesSpy).toHaveBeenCalledTimes(1);
    });

    it('scans at most 100 stored keys per request under high cardinality', async () => {
      jest.useFakeTimers();
      jest.setSystemTime(1_000);

      const middleware = rateLimitMiddleware({
        windowMs: 120_000,
        maxRequests: 2,
        keyGenerator: context => context.deviceId ?? 'unknown',
      });

      for (let index = 0; index <= 1_000; index++) {
        await middleware(createContext({ deviceId: `device-${index}` }), async () =>
          new Response('ok')
        );
      }

      const originalEntries = Map.prototype.entries;
      let scanned = 0;
      jest.spyOn(Map.prototype, 'entries').mockImplementation(function <K, V>(this: Map<K, V>) {
        const iterator = originalEntries.call(this);
        return {
          next() {
            scanned++;
            return iterator.next();
          },
          [Symbol.iterator]() {
            return this;
          },
        } as MapIterator<[K, V]>;
      });

      await middleware(createContext({ deviceId: 'overflow' }), async () => new Response('ok'));

      expect(scanned).toBe(100);
    });

    it('eventually reclaims expired high-cardinality entries in bounded batches', async () => {
      jest.useFakeTimers();
      jest.setSystemTime(1_000);

      const middleware = rateLimitMiddleware({
        windowMs: 100,
        maxRequests: 1,
        keyGenerator: context => context.deviceId ?? 'unknown',
      });

      for (let index = 0; index <= 1_000; index++) {
        await middleware(createContext({ deviceId: `expired-${index}` }), async () =>
          new Response('ok')
        );
      }

      jest.setSystemTime(1_101);
      const originalEntries = Map.prototype.entries;
      let scanned = 0;
      jest.spyOn(Map.prototype, 'entries').mockImplementation(function <K, V>(this: Map<K, V>) {
        const iterator = originalEntries.call(this);
        return {
          next() {
            scanned++;
            return iterator.next();
          },
          [Symbol.iterator]() {
            return this;
          },
        } as MapIterator<[K, V]>;
      });

      for (let index = 0; index < 12; index++) {
        await middleware(createContext({ deviceId: `fresh-${index}` }), async () =>
          new Response('ok')
        );
      }

      expect(scanned).toBeLessThanOrEqual(1_200);
      expect(scanned).toBeGreaterThanOrEqual(1_001);

      const scannedAfterCleanup = scanned;
      await middleware(createContext({ deviceId: 'post-cleanup' }), async () => new Response('ok'));
      expect(scanned).toBe(scannedAfterCleanup);
    });
  });

  describe('createDefaultPipeline', () => {
    it.each([
      undefined,
      { enableCORS: true },
      { enableRateLimit: true },
      { enableSecurity: false, enableLogging: false },
    ])('creates a pipeline for options %j', options => {
      expect(createDefaultPipeline(options)).toBeInstanceOf(MiddlewarePipeline);
    });
  });
});
