import { CicadaRelayApp } from '../../src/presentation/app';
import type { Env } from '../../src/types';

describe('Shortcuts gateway malicious input handling', () => {
  let app: CicadaRelayApp;
  let mockEnv: Env;
  let mockCtx: ExecutionContext;

  const registryFetch = jest.fn(async (request: Request) => {
    const authorization = request.headers.get('Authorization') ?? '';
    if (!authorization.startsWith('Bearer cicada_sc_')) {
      return Response.json(
        { ok: false, code: 'invalid_token', error: 'Shortcut token is missing or malformed.' },
        { status: 401 }
      );
    }

    const body = (await request.json().catch(() => null)) as {
      device_id?: unknown;
      command?: unknown;
    } | null;
    if (!body || typeof body.device_id !== 'string' || typeof body.command !== 'string') {
      return Response.json(
        { ok: false, code: 'invalid_shortcut_command', error: 'Invalid shortcut command.' },
        { status: 400 }
      );
    }

    return Response.json(
      { ok: false, code: 'invalid_token', error: 'Shortcut token is invalid.' },
      { status: 401 }
    );
  });

  beforeEach(() => {
    registryFetch.mockClear();
    mockEnv = {
      ENABLE_CORS: 'false',
      RATE_LIMIT_ENABLED: 'false',
      DEBUG_MODE: 'false',
      CICADA_SESSIONS: {
        idFromName: jest.fn((name: string) => ({ name })),
        get: jest.fn(() => ({ fetch: registryFetch })),
      } as any,
    };

    mockCtx = {
      waitUntil: jest.fn(),
      passThroughOnException: jest.fn(),
    } as any;

    app = new CicadaRelayApp(mockEnv);
  });

  const createPostRequest = (
    body: unknown,
    authorization = 'Bearer cicada_sc_invalid_token'
  ): Request => {
    return new Request('http://localhost/v1/shortcuts/command', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: authorization,
      },
      body: JSON.stringify(body),
    });
  };

  it.each([
    "' OR '1'='1",
    "'; DROP TABLE users; --",
    '<script>alert("XSS")</script>',
    '../../../etc/passwd',
    'MAC_1234567890ABCDEF\x001234567890ABCDEF',
  ])('rejects suspicious device_id input: %s', async malicious => {
    const response = await app.handle(
      createPostRequest({
        device_id: malicious,
        command: 'ping',
      }),
      mockEnv,
      mockCtx
    );

    expect(response.status).toBeGreaterThanOrEqual(400);
  });

  it.each([
    "ping'; DROP TABLE commands; --",
    'ping && cat /etc/passwd',
    'ping`whoami`',
    '<svg onload=alert("XSS")>',
    'ping\u0000',
  ])('rejects suspicious command input: %s', async malicious => {
    const response = await app.handle(
      createPostRequest({
        device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
        command: malicious,
      }),
      mockEnv,
      mockCtx
    );

    expect(response.status).toBeGreaterThanOrEqual(400);
  });

  it.each([
    { device_id: 123, command: 'ping' },
    { device_id: true, command: 'ping' },
    { device_id: null, command: 'ping' },
    { device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF', command: 123 },
    { device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF', command: null },
  ])('rejects non-string shortcut command fields', async payload => {
    const response = await app.handle(createPostRequest(payload), mockEnv, mockCtx);

    expect(response.status).toBeGreaterThanOrEqual(400);
  });

  it('rejects malformed shortcut authorization', async () => {
    const response = await app.handle(
      createPostRequest(
        {
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          command: 'ping',
        },
        'Bearer invalid-token'
      ),
      mockEnv,
      mockCtx
    );

    expect(response.status).toBe(401);
  });

  it('rejects oversized JSON payloads before dispatch', async () => {
    const hugeParams: Record<string, string> = {};
    for (let i = 0; i < 1000; i++) {
      hugeParams[`key${i}`] = 'A'.repeat(1000);
    }

    const response = await app.handle(
      createPostRequest({
        device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
        command: 'ping',
        data: hugeParams,
      }),
      mockEnv,
      mockCtx
    );

    expect(response.status).toBeGreaterThanOrEqual(400);
  });
});
