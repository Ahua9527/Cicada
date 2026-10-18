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

    mockEnv = withRegistry(url => {
      if (url.pathname === '/registry/status') {
        return Response.json({
          success: true,
          totalDevices: 0,
          activeDevices: 0,
          totalSessions: 0,
          activeConnections: 0,
        });
      }
      if (url.pathname === '/registry/devices') {
        return Response.json({ success: true, devices: [], total: 0, active: 0 });
      }
      return Response.json({ success: false }, { status: 404 });
    });
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
    it('should return health status after probing the registry once', async () => {
      const paths: string[] = [];
      mockEnv = withRegistry(url => {
        paths.push(url.pathname);
        return Response.json({
          success: true,
          totalDevices: 0,
          activeDevices: 0,
          totalSessions: 0,
          activeConnections: 0,
        });
      });
      app = new CicadaRelayApp(mockEnv);
      const request = new Request('http://localhost/health', { method: 'GET' });
      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any;

      expect(response.status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.status).toBe('healthy');
      expect(paths).toEqual(['/registry/status']);
      expect(data.checks).toEqual({ api: 'ok', durableObjects: 'ok' });
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
      for (const field of ['uptime', 'totalCommands', 'commandsPerSecond', 'memoryUsage']) {
        expect(data.data).not.toHaveProperty(field);
      }
      expect(data.data.durableObjectStats).not.toHaveProperty('messagesQueued');
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

  describe('Registry availability', () => {
    for (const path of [
      '/health',
      '/devices',
      '/status',
      '/status?device_id=MAC_1234567890ABCDEF1234567890ABCDEF',
    ]) {
      for (const failure of ['missing binding', 'fetch throws', 'non-2xx response']) {
        it(`returns 503 for ${path} when the registry has ${failure}`, async () => {
          if (failure === 'missing binding') {
            mockEnv = { ...mockEnv, CICADA_SESSIONS: undefined } as unknown as Env;
          } else {
            mockEnv = withRegistry(() => {
              if (failure === 'fetch throws') {
                throw new Error('private registry failure');
              }
              return new Response('private registry failure', { status: 502 });
            });
          }
          app = new CicadaRelayApp(mockEnv);

          const response = await app.handle(
            new Request(`http://localhost${path}`),
            mockEnv,
            mockCtx
          );
          const data = (await response.json()) as any;

          expect(response.status).toBe(503);
          expect(data).toEqual({
            ok: false,
            error: 'Internal server error',
            request_id: expect.any(String),
          });
          expect(response.headers.get('X-Request-ID')).toBe(data.request_id);
        });
      }
    }

    it('reports an unknown device as offline only after a successful registry read', async () => {
      const deviceId = 'MAC_1234567890ABCDEF1234567890ABCDEF';
      const response = await app.handle(
        new Request(`http://localhost/status?device_id=${deviceId}`),
        mockEnv,
        mockCtx
      );

      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({
        ok: true,
        data: { deviceId, connected: false },
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

    // 流式 body（无 content-length 或可控 content-length）用于验证绕过防护：
    // content-length 缺失/少报/畸形时仍按实际字节计数并拒绝超限请求。
    const oversizedStream = (contentLength?: string) => {
      const body = 'x'.repeat(20 * 1024);
      const stream = new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode(body));
          controller.close();
        },
      });
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (contentLength !== undefined) {
        headers['Content-Length'] = contentLength;
      }
      // duplex 为 undici/Node 运行时对流式 body 的要求；workers-types 的 RequestInit 未声明它，
      // 先赋值给变量再传入以绕过对象字面量的多余属性检查。
      const init = {
        method: 'POST',
        headers,
        body: stream,
        duplex: 'half' as const,
      };
      return new Request('http://localhost/v1/shortcuts/command', init);
    };

    it('rejects an oversized body with no content-length', async () => {
      const response = await app.handle(oversizedStream(), mockEnv, mockCtx);
      const data = (await response.json()) as any;
      expect(response.status).toBe(413);
      expect(data.ok).toBe(false);
    });

    it('rejects an oversized body with an understated content-length', async () => {
      const response = await app.handle(oversizedStream('100'), mockEnv, mockCtx);
      const data = (await response.json()) as any;
      expect(response.status).toBe(413);
      expect(data.ok).toBe(false);
    });

    it('rejects an oversized body with a malformed content-length', async () => {
      const response = await app.handle(oversizedStream('abc'), mockEnv, mockCtx);
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

  describe('POST /v1/admin/device-reset', () => {
    const deviceId = 'MAC_2C501BC5B5D74431ADB19AFE30CD9CD3';
    const ADMIN_TOKEN = 'test-admin-token';

    const resetRequest = (token: string | undefined, bodyDeviceId: string = deviceId) =>
      new Request('http://localhost/v1/admin/device-reset', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        body: JSON.stringify({ device_id: bodyDeviceId }),
      });

    it('returns 404 when CICADA_ADMIN_TOKEN is not configured', async () => {
      const response = await app.handle(resetRequest(ADMIN_TOKEN), mockEnv, mockCtx);
      expect(response.status).toBe(404);
    });

    it('returns 401 for a wrong or missing bearer token', async () => {
      const env = { ...mockEnv, CICADA_ADMIN_TOKEN: ADMIN_TOKEN };

      const wrong = await app.handle(resetRequest('wrong-token'), env, mockCtx);
      const missing = await app.handle(resetRequest(undefined), env, mockCtx);

      expect(wrong.status).toBe(401);
      expect(missing.status).toBe(401);
    });

    it('returns 400 for an invalid device_id', async () => {
      const env = { ...mockEnv, CICADA_ADMIN_TOKEN: ADMIN_TOKEN };
      const response = await app.handle(resetRequest(ADMIN_TOKEN, 'bogus'), env, mockCtx);
      expect(response.status).toBe(400);
    });

    it('forwards the reset to the registry DO with the right token', async () => {
      let hitPath = '';
      const env = {
        ...withRegistry(url => {
          hitPath = url.pathname;
          return Response.json({ ok: true, deviceId, existed: true });
        }),
        CICADA_ADMIN_TOKEN: ADMIN_TOKEN,
      };

      const response = await app.handle(resetRequest(ADMIN_TOKEN), env, mockCtx);
      const data = (await response.json()) as { ok: boolean; existed: boolean };

      expect(response.status).toBe(200);
      expect(data.ok).toBe(true);
      expect(data.existed).toBe(true);
      expect(hitPath).toBe('/registry/admin-reset-device');
    });
  });
});
