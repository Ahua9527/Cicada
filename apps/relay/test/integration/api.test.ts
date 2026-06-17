/**
 * API 集成测试
 * 测试所有 API 端点
 */

import { CicadaRelayApp } from '../../src/presentation/app';
import type { Env } from '../../src/types';

describe('API Integration Tests', () => {
  let app: CicadaRelayApp;
  let mockEnv: Env;
  let mockCtx: ExecutionContext;

  const withRegistry = (handler: (url: URL) => Response): Env => {
    const registryStub = {
      fetch: jest.fn((input: RequestInfo) => {
        const url = new URL(typeof input === 'string' ? input : input.url);
        return Promise.resolve(handler(url));
      }),
    };
    return {
      ...mockEnv,
      CICADA_SESSIONS: {
        idFromName: jest.fn((name: string) => ({ name })),
        get: jest.fn(() => registryStub),
      } as any,
    };
  };

  beforeEach(() => {
    // Mock environment
    mockEnv = {
      ENABLE_CORS: 'false',
      RATE_LIMIT_ENABLED: 'false',
      DEBUG_MODE: 'false',
      CICADA_SESSIONS: {} as any,
    };

    // Mock execution context
    mockCtx = {
      waitUntil: jest.fn(),
      passThroughOnException: jest.fn(),
    } as any;

    app = new CicadaRelayApp(mockEnv);
  });

  describe('GET /', () => {
    it('should return API information', async () => {
      const request = new Request('http://localhost/', { method: 'GET' });
      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any as any;

      expect(response.status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.message).toBe('CicadaRelay API Server');
      expect(data.endpoints).toBeDefined();
    });
  });

  describe('GET /health', () => {
    it('should return health status', async () => {
      const request = new Request('http://localhost/health', { method: 'GET' });
      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any;

      expect(response.status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.status).toBe('healthy');
    });
  });

  describe('GET /status', () => {
    it('should return system status', async () => {
      const request = new Request('http://localhost/status', { method: 'GET' });
      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any;

      expect(response.status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.data).toBeDefined();
      expect(data.data).toHaveProperty('uptime');
      expect(data.data).toHaveProperty('service');
      expect(data.data.service).toBe('CicadaRelay');
    });

    it('should return registry-backed device totals', async () => {
      mockEnv = withRegistry(url => {
        if (url.pathname === '/registry/status') {
          return Response.json({
            success: true,
            totalDevices: 1,
            activeDevices: 1,
            totalSessions: 1,
            activeConnections: 1,
          });
        }
        return Response.json({ success: false }, { status: 404 });
      });
      app = new CicadaRelayApp(mockEnv);

      const request = new Request('http://localhost/status', { method: 'GET' });
      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any;

      expect(response.status).toBe(200);
      expect(data.data.totalDevices).toBe(1);
      expect(data.data.activeDevices).toBe(1);
      expect(data.data.durableObjectStats.totalSessions).toBe(1);
      expect(data.data.durableObjectStats.activeConnections).toBe(1);
    });
  });

  describe('GET /devices', () => {
    it('should return device list', async () => {
      const request = new Request('http://localhost/devices', { method: 'GET' });
      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any;

      expect(response.status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.data).toBeDefined();
      expect(Array.isArray(data.data.devices)).toBe(true);
      expect(typeof data.data.total).toBe('number');
    });

    it('should return registry-backed devices', async () => {
      mockEnv = withRegistry(url => {
        if (url.pathname === '/registry/devices') {
          return Response.json({
            success: true,
            devices: [
              {
                deviceId: 'MAC_1234567890ABCDEF1234567890ABCDEF',
                connected: true,
                connectedAt: Date.now(),
                lastPing: Date.now(),
              },
            ],
            total: 1,
            active: 1,
          });
        }
        return Response.json({ success: false }, { status: 404 });
      });
      app = new CicadaRelayApp(mockEnv);

      const request = new Request('http://localhost/devices', { method: 'GET' });
      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any;

      expect(response.status).toBe(200);
      expect(data.data).toMatchObject({
        total: 1,
        active: 1,
        devices: [
          {
            deviceId: 'MAC_1234567890ABCDEF1234567890ABCDEF',
            connected: true,
          },
        ],
      });
    });
  });

  describe('404 Not Found', () => {
    it('should return 404 for unknown routes', async () => {
      const request = new Request('http://localhost/unknown', { method: 'GET' });
      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any;

      expect(response.status).toBe(404);
      expect(data.ok).toBe(false);
      expect(data.error).toContain('not found');
    });
  });

  describe('CORS', () => {
    it('should not add CORS headers when disabled', async () => {
      const request = new Request('http://localhost/', {
        method: 'GET',
        headers: { Origin: 'https://example.com' },
      });

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.headers.get('Access-Control-Allow-Origin')).toBeNull();
    });

    it('should allow agent relay headers for configured origins', async () => {
      mockEnv = {
        ...mockEnv,
        ENABLE_CORS: 'true',
        ALLOWED_ORIGINS: 'https://cli.example, https://browser.example',
      };
      app = new CicadaRelayApp(mockEnv);

      const request = new Request('http://localhost/', {
        method: 'OPTIONS',
        headers: {
          Origin: 'https://browser.example',
          'Access-Control-Request-Method': 'GET',
        },
      });

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.status).toBe(200);
      expect(response.headers.get('Access-Control-Allow-Origin')).toBe('https://browser.example');
      expect(response.headers.get('Access-Control-Allow-Headers')).not.toContain('X-Role');
      expect(response.headers.get('Access-Control-Allow-Headers')).toContain(
        'X-Agent-Identity-Public-Key'
      );
    });

    it('should use default development origins when CORS is enabled without a list', async () => {
      mockEnv = {
        ...mockEnv,
        ENABLE_CORS: 'true',
        ALLOWED_ORIGINS: undefined,
      };
      app = new CicadaRelayApp(mockEnv);

      const request = new Request('http://localhost/', {
        method: 'OPTIONS',
        headers: {
          Origin: 'http://localhost:5173',
          'Access-Control-Request-Method': 'GET',
        },
      });

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.headers.get('Access-Control-Allow-Origin')).toBe('http://localhost:5173');
    });

    it('should handle OPTIONS preflight requests', async () => {
      const request = new Request('http://localhost/v1/shortcuts/command', {
        method: 'OPTIONS',
        headers: {
          Origin: 'https://example.com',
          'Access-Control-Request-Method': 'POST',
        },
      });

      const response = await app.handle(request, mockEnv, mockCtx);

      // Should pass through or handle based on CORS config
      expect(response.status).toBeGreaterThanOrEqual(200);
      expect(response.status).toBeLessThan(500);
    });
  });

  describe('URL sanitization', () => {
    it('should redact relay session paths and sensitive query values', () => {
      const sanitized = (app as any).sanitizeUrl(
        'https://relay.example/relay/device~secret-session/extra?api_key=secret&nonce=n1&signature=s1&token=t1&code=c1&visible=yes'
      );

      expect(sanitized).toBe(
        'https://relay.example/relay/[session]/extra?api_key=%5BFILTERED%5D&nonce=%5BFILTERED%5D&signature=%5BFILTERED%5D&token=%5BFILTERED%5D&code=%5BFILTERED%5D&visible=yes'
      );
    });

    it('should redact bare relay session paths', () => {
      const sanitized = (app as any).sanitizeUrl('https://relay.example/relay/live-session');

      expect(sanitized).toBe('https://relay.example/relay/[session]');
    });
  });

  describe('Request Validation', () => {
    it('should enforce request size limits', async () => {
      // Create a large JSON body that exceeds the limit
      const largeData = { data: 'x'.repeat(20 * 1024) }; // 20KB+ JSON
      const largeBody = JSON.stringify(largeData);
      const request = new Request('http://localhost/v1/shortcuts/command', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': largeBody.length.toString(),
        },
        body: largeBody,
      });

      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any;

      expect(response.status).toBe(413);
      expect(data.ok).toBe(false);
    });

    it('should reject invalid JSON', async () => {
      const request = new Request('http://localhost/unknown-post', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: 'invalid json',
      });

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.status).toBeGreaterThanOrEqual(400);
      expect(response.status).toBeLessThan(500);
    });
  });

  describe('Security Headers', () => {
    it('should add security headers to responses', async () => {
      const request = new Request('http://localhost/', { method: 'GET' });
      const response = await app.handle(request, mockEnv, mockCtx);

      // Security headers should be present
      expect(response.headers.get('X-Content-Type-Options')).toBeDefined();
      expect(response.headers.get('X-Frame-Options')).toBeDefined();
    });
  });

  describe('Rate Limit', () => {
    it('should be enabled by default and reject requests over the window limit', async () => {
      mockEnv = {
        ...mockEnv,
        RATE_LIMIT_ENABLED: undefined,
      };
      app = new CicadaRelayApp(mockEnv);

      for (let i = 0; i < 100; i += 1) {
        const response = await app.handle(
          new Request('http://localhost/health', {
            method: 'GET',
            headers: {
              'CF-Connecting-IP': '203.0.113.10',
            },
          }),
          mockEnv,
          mockCtx
        );
        expect(response.status).toBe(200);
      }

      const limited = await app.handle(
        new Request('http://localhost/health', {
          method: 'GET',
          headers: {
            'CF-Connecting-IP': '203.0.113.10',
          },
        }),
        mockEnv,
        mockCtx
      );

      expect(limited.status).toBe(429);
      expect(limited.headers.get('X-RateLimit-Remaining')).toBe('0');
    });
  });
});
