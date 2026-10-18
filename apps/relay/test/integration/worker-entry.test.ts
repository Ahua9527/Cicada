import worker from '../../src/index';
import type { Env } from '../../src/types';

describe('Worker entry rate limiting', () => {
  it('should retain per-IP counts across fetch calls and reject the 101st request', async () => {
    const env = {
      CICADA_SESSIONS: {
        idFromName: jest.fn(() => ({ name: 'registry' })),
        get: jest.fn(() => ({
          fetch: jest.fn(() =>
            Promise.resolve(
              Response.json({
                success: true,
                totalDevices: 0,
                activeDevices: 0,
                totalSessions: 0,
                activeConnections: 0,
              })
            )
          ),
        })),
      },
    } as unknown as Env;
    const ctx = {
      waitUntil: jest.fn(),
      passThroughOnException: jest.fn(),
    } as unknown as ExecutionContext;

    // The module-level app is shared across test files in this process.
    // Other tests using this entry must use different client IPs.
    const fetchHealth = () =>
      worker.fetch(
        new Request('http://localhost/health', {
          method: 'GET',
          headers: { 'CF-Connecting-IP': '203.0.113.247' },
        }),
        env,
        ctx
      );

    for (let i = 0; i < 100; i += 1) {
      const response = await fetchHealth();
      expect(response.status).toBe(200);
    }

    const limited = await fetchHealth();
    expect(limited.status).toBe(429);
    expect(limited.headers.get('X-RateLimit-Remaining')).toBe('0');
  });
});
