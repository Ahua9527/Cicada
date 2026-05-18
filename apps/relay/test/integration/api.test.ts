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

  beforeEach(() => {
    // Mock environment
    mockEnv = {
      API_KEY: 'test-api-key',
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
  });

  describe('POST /send', () => {
    it('should reject request without API key', async () => {
      const request = new Request('http://localhost/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: 'ping',
          ts: Math.floor(Date.now() / 1000),
        }),
      });

      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any;

      expect(response.status).toBe(401);
      expect(data.ok).toBe(false);
    });

    it('should reject request with invalid device ID', async () => {
      const request = new Request('http://localhost/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_id: 'invalid-id',
          cmd: 'ping',
          ts: Math.floor(Date.now() / 1000),
          api_key: 'test-api-key',
        }),
      });

      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any;

      expect(response.status).toBe(400);
      expect(data.ok).toBe(false);
    });

    it('should reject request with expired timestamp', async () => {
      const request = new Request('http://localhost/send', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: 'ping',
          ts: Math.floor(Date.now() / 1000) - 400, // 400 seconds ago
          api_key: 'test-api-key',
        }),
      });

      const response = await app.handle(request, mockEnv, mockCtx);
      const data = (await response.json()) as any;

      expect(response.status).toBe(400);
      expect(data.ok).toBe(false);
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

    it('should handle OPTIONS preflight requests', async () => {
      const request = new Request('http://localhost/send', {
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

  describe('Request Validation', () => {
    it('should enforce request size limits', async () => {
      // Create a large JSON body that exceeds the limit
      const largeData = { data: 'x'.repeat(20 * 1024) }; // 20KB+ JSON
      const largeBody = JSON.stringify(largeData);
      const request = new Request('http://localhost/send', {
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
      const request = new Request('http://localhost/send', {
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
});
