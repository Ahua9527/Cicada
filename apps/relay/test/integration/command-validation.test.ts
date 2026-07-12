import { CicadaRelayApp } from '../../src/presentation/app';
import type { Env } from '../../src/types';

describe('deleted legacy command and controller routes', () => {
  let app: CicadaRelayApp;
  let mockEnv: Env;
  let mockCtx: ExecutionContext;

  beforeEach(() => {
    mockEnv = {
      ENABLE_CORS: 'false',
      RATE_LIMIT_ENABLED: 'false',
      DEBUG_MODE: 'false',
      CICADA_SESSIONS: {} as any,
    };

    mockCtx = {
      waitUntil: jest.fn(),
      passThroughOnException: jest.fn(),
    } as any;

    app = new CicadaRelayApp(mockEnv);
  });

  it.each([
    ['POST', '/send'],
    ['POST', '/api/command'],
    ['POST', '/v1/pairing/code/resolve'],
    ['POST', '/v1/trusted/device/connect'],
    ['GET', '/ws'],
    ['GET', '/api/devices'],
    ['GET', '/api/sessions'],
    ['GET', '/bark'],
    ['POST', '/bark/device-key/title/body'],
  ])('%s %s is not registered', async (method, path) => {
    const response = await app.handle(
      new Request(`http://localhost${path}`, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: method === 'GET' ? undefined : '{}',
      }),
      mockEnv,
      mockCtx
    );

    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toMatchObject({
      ok: false,
      error: 'API endpoint not found',
      path,
    });
  });

  it('ignores legacy Bark root path configuration', async () => {
    const legacyEnv = { ...mockEnv, BARK_ROOT_PATH: '/push' } as Env;
    const response = await app.handle(
      new Request('http://localhost/push/device-key/title/body'),
      legacyEnv,
      mockCtx
    );

    expect(response.status).toBe(404);
    await expect(response.json()).resolves.toMatchObject({
      ok: false,
      error: 'API endpoint not found',
      path: '/push/device-key/title/body',
    });
  });
});
