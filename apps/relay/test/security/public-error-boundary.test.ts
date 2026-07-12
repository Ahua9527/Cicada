import { Logger as WorkerLogger } from '../../src/infrastructure/logger';
import { MiddlewarePipeline } from '../../src/infrastructure/middleware';
import type { MiddlewareContext } from '../../src/infrastructure/middleware/types';
import { SessionManagerDO } from '../../src/infrastructure/persistence';
import { CicadaRelayApp } from '../../src/presentation/app';
import { DeviceController } from '../../src/presentation/controllers/device.controller';
import { SessionController } from '../../src/presentation/controllers/session.controller';
import { enforcePublicServerErrorResponse } from '../../src/presentation/public-error-response';
import { Router } from '../../src/presentation/router';
import { handleWebSocketRoute } from '../../src/presentation/routes/websocket.route';
import type { Env } from '../../src/types';
import { Logger as LegacyLogger } from '../../src/utils/logger';

const requestId = 'req-public-error-test';
const secret = 'authorization=Bearer should-not-leak token=relay-token nonce=nonce-value';

const createContext = (overrides: Partial<MiddlewareContext> = {}): MiddlewareContext => {
  const request = new Request('https://relay.example.com/test');
  return {
    request,
    env: {} as Env,
    requestId,
    logger: new WorkerLogger({ enableConsole: false }) as any,
    timestamp: Date.now(),
    url: new URL(request.url),
    method: request.method,
    headers: {},
    ...overrides,
  };
};

const createMockState = (name = 'test-session'): DurableObjectState =>
  ({
    id: {
      toString: () => name,
      equals: jest.fn(),
      name,
    },
    storage: {
      get: jest.fn().mockResolvedValue(null),
      put: jest.fn().mockResolvedValue(undefined),
      delete: jest.fn().mockResolvedValue(undefined),
      list: jest.fn().mockResolvedValue(new Map()),
    },
    blockConcurrencyWhile: jest.fn(async (callback: () => Promise<void>) => callback()),
    waitUntil: jest.fn(),
  }) as any;

const expectPublicServerError = async (response: Response, expectedRequestId = requestId) => {
  const body = await response.json();
  expect(response.status).toBe(500);
  expect(body).toEqual({
    ok: false,
    error: 'Internal server error',
    request_id: expectedRequestId,
  });
  expect(response.headers.get('X-Request-ID')).toBe(expectedRequestId);
  expect(JSON.stringify([...response.headers])).not.toContain('should-not-leak');
};

describe('public server error boundary', () => {
  it.each([503, 504])('preserves %i status while replacing the public body', async status => {
    const response = enforcePublicServerErrorResponse(
      new Response(secret, {
        status,
        headers: {
          'X-Internal-Error': secret,
          'Cache-Control': 'no-store',
        },
      }),
      requestId
    );

    expect(response.status).toBe(status);
    expect(await response.json()).toEqual({
      ok: false,
      error: 'Internal server error',
      request_id: requestId,
    });
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(response.headers.get('X-Internal-Error')).toBeNull();
    expect(JSON.stringify([...response.headers])).not.toContain('should-not-leak');
  });

  it.each([400, 401, 403, 404, 409, 429])('leaves %i responses unchanged', status => {
    const response = Response.json({ ok: false, error: `client error ${status}` }, { status });

    expect(enforcePublicServerErrorResponse(response, requestId)).toBe(response);
  });

  it('leaves WebSocket 101 responses unchanged', () => {
    const response = { status: 101 } as Response;

    expect(enforcePublicServerErrorResponse(response, requestId)).toBe(response);
  });

  it.each(['/test', '/relay/live-session'])(
    'sanitizes middleware exceptions for %s',
    async pathname => {
      const pipeline = new MiddlewarePipeline();
      pipeline.use(async () => {
        throw new Error(`${secret} path=/Users/private/relay.ts`);
      });
      const context = createContext({
        request: new Request(`https://relay.example.com${pathname}`),
        url: new URL(`https://relay.example.com${pathname}`),
      });

      await expectPublicServerError(await pipeline.execute(context));
    }
  );

  it('sanitizes router handler exceptions', async () => {
    const router = new Router();
    (router as any).routes = [
      {
        pattern: /^\/test$/,
        methods: ['GET'],
        handler: async () => {
          throw new Error(secret);
        },
      },
    ];

    const result = await router.createMiddleware()(createContext(), async () => ({
      continue: true,
    }));

    await expectPublicServerError((result as any).response);
  });

  it('sanitizes WebSocket route exceptions', async () => {
    jest
      .spyOn(SessionController, 'handleWebSocketConnection')
      .mockRejectedValueOnce(new Error(secret));

    await expectPublicServerError(await handleWebSocketRoute(createContext()));
  });

  it('sanitizes relay and registry controller exceptions', async () => {
    const throwingNamespace = {
      idFromName: jest.fn(() => ({ name: 'session' })),
      get: jest.fn(() => {
        throw new Error(secret);
      }),
    };
    const relayRequest = new Request('https://relay.example.com/relay/live-session', {
      headers: {
        'X-Device-ID': 'MAC_1234567890ABCDEF1234567890ABCDEF',
        'X-Agent-Identity-Public-Key': 'public-key',
      },
    });
    const relayContext = createContext({
      request: relayRequest,
      url: new URL(relayRequest.url),
      env: { CICADA_SESSIONS: throwingNamespace } as any,
    });

    await expectPublicServerError(
      await SessionController.handleWebSocketConnection(relayContext)
    );
    await expectPublicServerError(
      await SessionController.sendShortcutCommand(
        createContext({ env: { CICADA_SESSIONS: throwingNamespace } as any })
      )
    );
  });

  it('forwards the public request ID to Durable Objects', async () => {
    const fetch = jest.fn().mockResolvedValue(Response.json({ ok: true }));
    const request = new Request('https://relay.example.com/relay/live-session', {
      headers: {
        'X-Device-ID': 'MAC_1234567890ABCDEF1234567890ABCDEF',
        'X-Agent-Identity-Public-Key': 'public-key',
      },
    });
    const context = createContext({
      request,
      url: new URL(request.url),
      env: {
        CICADA_SESSIONS: {
          idFromName: jest.fn(() => ({ name: 'session' })),
          get: jest.fn(() => ({ fetch })),
        },
      } as any,
    });

    await SessionController.handleWebSocketConnection(context);

    const forwardedRequest = fetch.mock.calls[0][0] as Request;
    expect(forwardedRequest.headers.get('X-Request-ID')).toBe(requestId);
  });

  it('sanitizes controller 5xx responses', async () => {
    const context = createContext({
      env: {
        CICADA_SESSIONS: {
          idFromName: jest.fn(() => ({ name: 'registry' })),
          get: jest.fn(() => ({ fetch: jest.fn().mockRejectedValue(new Error(secret)) })),
        },
      } as any,
    });

    await expectPublicServerError(await DeviceController.getDeviceList(context));
  });

  it('uses the final middleware request ID at the application boundary', async () => {
    const env = {
      ENABLE_CORS: 'false',
      RATE_LIMIT_ENABLED: 'false',
      CICADA_SESSIONS: {} as any,
    } as Env;
    const app = new CicadaRelayApp(env);
    (app as any).pipeline.execute = jest.fn(async (context: MiddlewareContext) => {
      context.requestId = 'req-from-middleware';
      throw new Error(secret);
    });

    const response = await app.handle(
      new Request('https://relay.example.com/test'),
      env,
      { waitUntil: jest.fn(), passThroughOnException: jest.fn() } as any
    );

    await expectPublicServerError(response, 'req-from-middleware');
    const errorLog = (app as any).logger
      .getRecentLogs()
      .find((entry: any) => entry.message === 'Request handling failed');
    expect(errorLog.requestId).toBe('req-from-middleware');
  });

  it('sanitizes Durable Object upgrade and fetch exceptions', async () => {
    const manager = new SessionManagerDO(createMockState(), {} as Env);
    const consoleError = jest.spyOn(console, 'error').mockImplementation(() => undefined);
    ((globalThis as any).WebSocketPair as jest.Mock).mockImplementationOnce(() => {
      throw new Error(secret);
    });

    const upgradeResponse = await manager.fetch(
      new Request('https://relay.example.com/relay/live-session', {
        headers: { Upgrade: 'websocket', 'X-Request-ID': requestId },
      })
    );
    await expectPublicServerError(upgradeResponse);

    (manager as any).handleRoomShortcutCommand = jest.fn().mockRejectedValue(new Error(secret));
    const fetchResponse = await manager.fetch(
      new Request('https://relay.example.com/shortcut/command', {
        method: 'POST',
        headers: { 'X-Request-ID': requestId },
      })
    );
    await expectPublicServerError(fetchResponse);

    const doLogs = consoleError.mock.calls.map(([entry]) => JSON.parse(String(entry)));
    expect(doLogs).toHaveLength(2);
    for (const entry of doLogs) {
      expect(entry.request_id).toBe(requestId);
      expect(entry.error.message).not.toContain('should-not-leak');
      expect(entry.error.stack).not.toContain('relay-token');
      expect(entry.error.stack).not.toContain('nonce-value');
    }
  });

  it.each([
    ['worker logger', () => new WorkerLogger({ enableConsole: false })],
    ['legacy logger', () => new LegacyLogger({ enableConsole: false })],
  ])('redacts sensitive Error message and stack in the %s', (_name, createLogger) => {
    const logger = createLogger();
    const error = new Error(secret);
    error.stack = `Error: ${secret}\n    at /Users/private/relay.ts:1:1`;

    logger.error('Request failed', { error });

    const loggedError = logger.getRecentLogs(1)[0].error;
    expect(loggedError?.name).toBe('Error');
    expect(loggedError?.message).not.toContain('should-not-leak');
    expect(loggedError?.message).not.toContain('relay-token');
    expect(loggedError?.message).not.toContain('nonce-value');
    expect(loggedError?.stack).toContain('/Users/private/relay.ts:1:1');
    expect(loggedError?.stack).not.toContain('should-not-leak');
  });
});
