import { readFileSync } from 'node:fs';
import { CicadaRelayApp } from '../../src/presentation/app';
import type { Env } from '../../src/types';

type SessionRow = {
  id: string;
  device_key: string | null;
  initialized: number;
  created_at: number;
  last_seen: number;
};

class MockD1Database {
  devices = new Map<string, string>();
  authorization?: { token: string; time: string };
  sessions = new Map<string, SessionRow>();

  exec = jest.fn();

  prepare(query: string) {
    let bindings: unknown[] = [];

    return {
      bind(...args: unknown[]) {
        bindings = args;
        return this;
      },
      run: async () => {
        if (query.includes('SELECT COUNT(*) as rowCount FROM `devices`')) {
          return { results: [{ rowCount: this.devices.size }] };
        }

        if (query.includes('SELECT `token` FROM `devices` WHERE `key` = ?')) {
          const key = String(bindings[0]);
          return { results: this.devices.has(key) ? [{ token: this.devices.get(key) }] : [] };
        }

        if (query.includes('INSERT INTO `devices`')) {
          this.devices.set(String(bindings[0]), String(bindings[1]));
          return { success: true, results: [] };
        }

        if (query.includes('DELETE FROM `devices` WHERE `key` = ?')) {
          this.devices.delete(String(bindings[0]));
          return { success: true, results: [] };
        }

        if (query.includes('INSERT INTO `authorization`')) {
          this.authorization = { token: String(bindings[0]), time: String(bindings[1]) };
          return { success: true, results: [] };
        }

        if (query.includes('SELECT `token`, `time` FROM `authorization`')) {
          return { results: this.authorization ? [this.authorization] : [] };
        }

        if (query.includes('SELECT `id`, `device_key`, `initialized` FROM `sessions`')) {
          const session = this.sessions.get(String(bindings[0]));
          return { results: session ? [session] : [] };
        }

        if (query.includes('INSERT INTO `sessions`')) {
          const [id, deviceKey, initialized, createdAt, lastSeen] = bindings;
          this.sessions.set(String(id), {
            id: String(id),
            device_key: deviceKey === null ? null : String(deviceKey),
            initialized: Number(initialized),
            created_at: Number(createdAt),
            last_seen: Number(lastSeen),
          });
          return { success: true, results: [] };
        }

        if (query.includes('DELETE FROM `sessions` WHERE `id` = ?')) {
          this.sessions.delete(String(bindings[0]));
          return { success: true, results: [] };
        }

        if (query.includes('DELETE FROM `sessions` WHERE `last_seen` < ?')) {
          return { success: true, results: [] };
        }

        throw new Error(`Unexpected D1 query: ${query}`);
      },
    };
  }
}

const createEnv = (overrides: Partial<Env> = {}): Env =>
  ({
    ENABLE_CORS: 'false',
    RATE_LIMIT_ENABLED: 'false',
    CICADA_SESSIONS: {} as any,
    BARK_DATABASE: new MockD1Database() as any,
    BARK_APNS_PRIVATE_KEY: [
      '-----BEGIN PRIVATE KEY-----',
      'MC4CAQAwBQYDK2VwBCIEIBERERERERERERERERERERERERERERERERERERERERER',
      '-----END PRIVATE KEY-----',
    ].join('\n'),
    BARK_APNS_TEAM_ID: 'TEAM123456',
    BARK_APNS_KEY_ID: 'KEY1234567',
    BARK_APNS_TOPIC: 'com.example.bark',
    ...overrides,
  }) as Env;

const createContext = (): ExecutionContext =>
  ({
    waitUntil: jest.fn(),
    passThroughOnException: jest.fn(),
  }) as any;

const readJson = async <T>(response: Response): Promise<T> => (await response.json()) as T;

describe('Bark vendor route', () => {
  let app: CicadaRelayApp;
  let env: Env;
  let ctx: ExecutionContext;
  let fetchMock: jest.Mock;

  beforeEach(() => {
    (crypto as Crypto & { randomUUID: jest.Mock }).randomUUID = jest
      .fn()
      .mockReturnValue('11111111-1111-4111-8111-111111111111');
    const digest = new Uint8Array(32).fill(7).buffer;
    (crypto.subtle.digest as jest.Mock).mockResolvedValue(digest);
    (crypto.subtle.importKey as jest.Mock).mockResolvedValue({ type: 'private' });
    (crypto.subtle.sign as jest.Mock).mockResolvedValue(new Uint8Array([1, 2, 3, 4]).buffer);

    fetchMock = jest.fn().mockResolvedValue(new Response('', { status: 200 }));
    global.fetch = fetchMock;

    env = createEnv();
    ctx = createContext();
    app = new CicadaRelayApp(env);
  });

  it('mounts ping and info under /bark with optional Basic Auth', async () => {
    const ping = await app.handle(new Request('http://localhost/bark/ping'), env, ctx);
    expect(ping.status).toBe(200);
    await expect(readJson<{ message: string }>(ping)).resolves.toMatchObject({ message: 'pong' });

    const healthz = await app.handle(new Request('http://localhost/bark/healthz'), env, ctx);
    expect(healthz.status).toBe(200);
    await expect(healthz.text()).resolves.toBe('ok');

    env = createEnv({ BARK_BASIC_AUTH: 'user:pass' });
    app = new CicadaRelayApp(env);

    const unauthorized = await app.handle(new Request('http://localhost/bark/info'), env, ctx);
    expect(unauthorized.status).toBe(401);

    const authorized = await app.handle(
      new Request('http://localhost/bark/info', {
        headers: { Authorization: `Basic ${btoa('user:pass')}` },
      }),
      env,
      ctx
    );
    expect(authorized.status).toBe(200);
    await expect(readJson<{ version: string; devices: number }>(authorized)).resolves.toMatchObject({
      version: 'v2.3.3',
      devices: 0,
    });
  });

  it('registers devices and forwards Bark push payloads to APNs', async () => {
    const register = await app.handle(
      new Request('http://localhost/bark/register?devicetoken=abc123'),
      env,
      ctx
    );
    expect(register.status).toBe(200);
    const body = await readJson<{ data: { device_key: string; device_token: string } }>(register);

    const push = await app.handle(
      new Request(`http://localhost/bark/${body.data.device_key}/Front%20Door/Motion?group=sentry`),
      env,
      ctx
    );
    expect(push.status).toBe(200);
    await expect(readJson<{ message: string }>(push)).resolves.toMatchObject({ message: 'success' });

    expect(fetchMock).toHaveBeenCalledWith(
      'https://api.push.apple.com/3/device/abc123',
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          'apns-topic': 'com.example.bark',
          'apns-push-type': 'alert',
          authorization: expect.stringMatching(/^bearer /),
        }),
      })
    );

    const apnsBody = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(apnsBody).toMatchObject({
      aps: {
        alert: {
          title: 'Front Door',
          body: 'Motion',
        },
        'thread-id': 'sentry',
      },
      group: 'sentry',
    });
  });

  it('preserves Bark path parameter parsing for title, subtitle, and body', async () => {
    const db = env.BARK_DATABASE as unknown as MockD1Database;
    db.devices.set('devicekey', 'devicetoken');

    const response = await app.handle(
      new Request('http://localhost/bark/devicekey/Front+Door/Camera/Motion%20detected'),
      env,
      ctx
    );

    expect(response.status).toBe(200);
    const payload = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(payload.aps.alert).toMatchObject({
      title: 'Front Door',
      subtitle: 'Camera',
      body: 'Motion detected',
    });
  });

  it('supports batch device_keys pushes', async () => {
    const db = env.BARK_DATABASE as unknown as MockD1Database;
    db.devices.set('alpha', 'tokenalpha');
    db.devices.set('beta', 'tokenbeta');

    const response = await app.handle(
      new Request('http://localhost/bark/push', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          device_keys: ['alpha', 'beta'],
          title: 'Alarm',
          body: 'Motion detected',
        }),
      }),
      env,
      ctx
    );

    expect(response.status).toBe(200);
    const result = await readJson<{ data: Array<{ code: number; device_key: string }> }>(response);
    expect(result.data).toEqual([
      { code: 200, message: 'success', device_key: 'alpha' },
      { code: 200, message: 'success', device_key: 'beta' },
    ]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('supports comma-separated batch device_keys and custom APNs host overrides', async () => {
    const db = env.BARK_DATABASE as unknown as MockD1Database;
    db.devices.set('alpha', 'tokenalpha');
    db.devices.set('beta', 'tokenbeta');
    env = createEnv({
      BARK_DATABASE: db as any,
      BARK_APNS_HOST_NAME: 'api.sandbox.push.apple.com',
    });
    app = new CicadaRelayApp(env);

    const response = await app.handle(
      new Request('http://localhost/bark/push?device_keys=alpha,beta&title=Alarm&body=Motion'),
      env,
      ctx
    );

    expect(response.status).toBe(200);
    expect(fetchMock.mock.calls.map(call => call[0])).toEqual([
      'https://api.sandbox.push.apple.com/3/device/tokenalpha',
      'https://api.sandbox.push.apple.com/3/device/tokenbeta',
    ]);
  });

  it('preserves Bark registration and request error responses', async () => {
    env = createEnv({ BARK_ALLOW_NEW_DEVICE: 'false' });
    app = new CicadaRelayApp(env);

    const disabled = await app.handle(
      new Request('http://localhost/bark/register?devicetoken=abc123'),
      env,
      ctx
    );
    expect(disabled.status).toBe(500);
    await expect(readJson<{ message: string }>(disabled)).resolves.toMatchObject({
      message: 'device registration failed: register disabled',
    });

    const malformed = await app.handle(
      new Request('http://localhost/bark/devicekey/%E0%A4%A'),
      env,
      ctx
    );
    expect(malformed.status).toBe(500);
    await expect(readJson<{ message: string }>(malformed)).resolves.toMatchObject({
      message: expect.stringContaining('url path parse failed'),
    });

    const missingDeviceKey = await app.handle(new Request('http://localhost/bark/push'), env, ctx);
    expect(missingDeviceKey.status).toBe(400);
    await expect(readJson<{ message: string }>(missingDeviceKey)).resolves.toMatchObject({
      message: 'device key is empty',
    });
  });

  it('serves MCP sessions through the vendored Bark handler', async () => {
    const init = await app.handle(
      new Request('http://localhost/bark/mcp', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize' }),
      }),
      env,
      ctx
    );
    expect(init.status).toBe(200);
    expect(init.headers.get('mcp-session-id')).toMatch(/^mcp-session-/);

    const sessionId = init.headers.get('mcp-session-id')!;
    const tools = await app.handle(
      new Request('http://localhost/bark/mcp', {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'mcp-session-id': sessionId },
        body: JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }),
      }),
      env,
      ctx
    );
    const toolsBody = await readJson<{ result: { tools: Array<{ name: string }> } }>(tools);
    expect(toolsBody.result.tools).toEqual([expect.objectContaining({ name: 'notify' })]);
  });

  it('can expose Bark at the Worker root without shadowing Cicada routes', async () => {
    env = createEnv({ BARK_ROOT_PATH: '/' });
    app = new CicadaRelayApp(env);

    const cicadaHealth = await app.handle(new Request('http://localhost/health'), env, ctx);
    expect(cicadaHealth.status).toBe(200);
    await expect(readJson<{ ok: boolean }>(cicadaHealth)).resolves.toMatchObject({ ok: true });

    const barkPing = await app.handle(new Request('http://localhost/ping'), env, ctx);
    expect(barkPing.status).toBe(200);
    await expect(readJson<{ message: string }>(barkPing)).resolves.toMatchObject({ message: 'pong' });
  });

  it('honors custom Bark root paths without keeping the default /bark mount', async () => {
    env = createEnv({ BARK_ROOT_PATH: '/push' });
    app = new CicadaRelayApp(env);

    const customPing = await app.handle(new Request('http://localhost/push/ping'), env, ctx);
    expect(customPing.status).toBe(200);
    await expect(readJson<{ message: string }>(customPing)).resolves.toMatchObject({ message: 'pong' });

    const defaultPing = await app.handle(new Request('http://localhost/bark/ping'), env, ctx);
    expect(defaultPing.status).toBe(404);
    await expect(readJson<{ error: string }>(defaultPing)).resolves.toMatchObject({
      error: 'API endpoint not found',
    });

    const legacySecretPath = await app.handle(
      new Request(
        'http://localhost/bark/devicekey/Front%20Door/Motion?devicetoken=abc123&group=sentry'
      ),
      env,
      ctx
    );
    expect(legacySecretPath.status).toBe(404);

    const logOutput = JSON.stringify((app as any).logger.getRecentLogs(20));
    expect(logOutput).toContain('/bark/[device_key]/[payload]');
    expect(logOutput).not.toContain('devicekey');
    expect(logOutput).not.toContain('abc123');
  });

  it('returns a clear service error when Bark D1 is not bound', async () => {
    env = createEnv({ BARK_DATABASE: undefined });
    app = new CicadaRelayApp(env);

    const response = await app.handle(new Request('http://localhost/bark/ping'), env, ctx);
    expect(response.status).toBe(503);
    await expect(readJson<{ error: string }>(response)).resolves.toMatchObject({
      error: 'Bark database binding is not configured',
    });
  });

  it('declares the Bark D1 binding in wrangler config', () => {
    const wrangler = readFileSync('wrangler.toml', 'utf8');

    expect(wrangler).toMatch(/^\[\[d1_databases\]\]$/m);
    expect(wrangler).toMatch(/^binding = "BARK_DATABASE"$/m);
    expect(wrangler).toMatch(/^migrations_dir = "vendor\/bark-worker\/migrations"$/m);
  });

  it('allows Bark MCP and delete preflights through CORS', async () => {
    env = createEnv({
      ENABLE_CORS: 'true',
      ALLOWED_ORIGINS: 'https://browser.example',
    });
    app = new CicadaRelayApp(env);

    const response = await app.handle(
      new Request('http://localhost/bark/mcp', {
        method: 'OPTIONS',
        headers: {
          Origin: 'https://browser.example',
          'Access-Control-Request-Method': 'DELETE',
          'Access-Control-Request-Headers': 'content-type,mcp-session-id',
        },
      }),
      env,
      ctx
    );

    expect(response.status).toBe(200);
    expect(response.headers.get('Access-Control-Allow-Methods')).toContain('DELETE');
    expect(response.headers.get('Access-Control-Allow-Headers')).toContain('mcp-session-id');
  });
});
