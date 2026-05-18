/**
 * 命令验证集成测试
 * 测试从 HTTP 请求到命令验证的完整流程
 */

import { CicadaRelayApp } from '../../src/presentation/app';
import type { Env } from '../../src/types';
import type { CommandRequest } from '@cicada/shared/types/command.types';

describe('命令验证集成测试', () => {
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

  /**
   * 创建有效的命令请求
   */
  const createValidRequest = (
    cmd: string,
    overrides: Partial<CommandRequest> = {}
  ): CommandRequest => {
    return {
      device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
      cmd,
      ts: Date.now(),
      api_key: 'test-api-key',
      ...overrides,
    };
  };

  /**
   * 创建 HTTP POST 请求
   */
  const createPostRequest = (body: any): Request => {
    return new Request('http://localhost/api/command', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
  };

  describe('端到端流程：支持的命令', () => {
    const supportedCommands = [
      'lock',
      'bt_toggle',
      'ping',
      'volume_mute',
      'sleep',
      'sleep_displays',
      'caffeinate',
      'decaffeinate',
      'status',
    ];

    supportedCommands.forEach(command => {
      it(`应该接受支持的命令: ${command}`, async () => {
        const requestBody = createValidRequest(command);
        const request = createPostRequest(requestBody);

        const response = await app.handle(request, mockEnv, mockCtx);

        // 验证响应状态码（可能是 200、202、404 或 500，取决于是否有 WebSocket 连接）
        // 重点是不应该因为命令验证失败（400 错误）
        expect(response.status).toBeDefined();

        // 如果返回 JSON，验证格式
        const contentType = response.headers.get('Content-Type');
        if (contentType?.includes('application/json')) {
          const data = (await response.json()) as any;
          expect(data).toBeDefined();

          // 如果是验证错误（400），不应该是命令不支持的错误
          if (response.status === 400 && !data.ok && data.error) {
            expect(data.error.toLowerCase()).not.toMatch(/unsupported|不支持/);
          }
        }
      });
    });
  });

  describe('端到端流程：不支持的命令', () => {
    const unsupportedCommands = ['bt_on', 'bt_off', 'invalid_command', 'shutdown', 'restart'];

    unsupportedCommands.forEach(command => {
      it(`应该拒绝不支持的命令: ${command}`, async () => {
        const requestBody = createValidRequest(command);
        const request = createPostRequest(requestBody);

        const response = await app.handle(request, mockEnv, mockCtx);

        // 应该返回错误响应
        expect(response.status).toBeGreaterThanOrEqual(400);

        const data = (await response.json()) as any;
        expect(data.ok).toBe(false);
        expect(data.error).toBeDefined();
        // 错误消息应该提到命令不支持
        expect(data.error.toLowerCase()).toMatch(/command|命令/);
      });
    });
  });

  describe('端到端流程：验证失败场景', () => {
    it('应该拒绝缺少 device_id 的请求', async () => {
      const requestBody = {
        cmd: 'lock',
        ts: Date.now(),
        api_key: 'test-api-key',
      };
      const request = createPostRequest(requestBody);

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.status).toBeGreaterThanOrEqual(400);
      const data = (await response.json()) as any;
      expect(data.ok).toBe(false);
      expect(data.error).toBeDefined();
      // 错误消息应该提到缺少字段
      expect(data.error.toUpperCase()).toMatch(/MISSING|REQUIRED|DEVICE_ID/);
    });

    it('应该拒绝缺少 cmd 的请求', async () => {
      const requestBody = {
        device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
        ts: Date.now(),
        api_key: 'test-api-key',
      };
      const request = createPostRequest(requestBody);

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.status).toBeGreaterThanOrEqual(400);
      const data = (await response.json()) as any;
      expect(data.ok).toBe(false);
      expect(data.error).toBeDefined();
      // 错误消息应该提到缺少字段
      expect(data.error.toUpperCase()).toMatch(/MISSING|REQUIRED|CMD/);
    });

    it('应该拒绝缺少 ts 的请求', async () => {
      const requestBody = {
        device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
        cmd: 'lock',
        api_key: 'test-api-key',
      };
      const request = createPostRequest(requestBody);

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.status).toBeGreaterThanOrEqual(400);
      const data = (await response.json()) as any;
      expect(data.ok).toBe(false);
      expect(data.error).toBeDefined();
      // 错误消息应该提到缺少字段
      expect(data.error.toUpperCase()).toMatch(/MISSING|REQUIRED|TS/);
    });

    it('应该拒绝无效的 device_id 格式', async () => {
      const requestBody = createValidRequest('lock', {
        device_id: 'invalid-device-id',
      });
      const request = createPostRequest(requestBody);

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.status).toBeGreaterThanOrEqual(400);
      const data = (await response.json()) as any;
      expect(data.ok).toBe(false);
      expect(data.error.toLowerCase()).toMatch(/device_id|format/);
    });

    it('应该拒绝过期的时间戳', async () => {
      // 创建一个 10 分钟前的时间戳（超过 5 分钟容忍度）
      const oldTimestamp = Date.now() - 10 * 60 * 1000;
      const requestBody = createValidRequest('lock', {
        ts: oldTimestamp,
      });
      const request = createPostRequest(requestBody);

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.status).toBeGreaterThanOrEqual(400);
      const data = (await response.json()) as any;
      expect(data.ok).toBe(false);
      expect(data.error.toLowerCase()).toMatch(/timestamp|时间戳/);
    });

    it('应该拒绝未来的时间戳', async () => {
      // 创建一个 10 分钟后的时间戳（超过 5 分钟容忍度）
      const futureTimestamp = Date.now() + 10 * 60 * 1000;
      const requestBody = createValidRequest('lock', {
        ts: futureTimestamp,
      });
      const request = createPostRequest(requestBody);

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.status).toBeGreaterThanOrEqual(400);
      const data = (await response.json()) as any;
      expect(data.ok).toBe(false);
      expect(data.error.toLowerCase()).toMatch(/timestamp|时间戳/);
    });

    it('应该拒绝错误的 API Key', async () => {
      const requestBody = createValidRequest('lock', {
        api_key: 'wrong-api-key',
      });
      const request = createPostRequest(requestBody);

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.status).toBeGreaterThanOrEqual(400);
      const data = (await response.json()) as any;
      expect(data.ok).toBe(false);
      expect(data.error.toLowerCase()).toMatch(/api_key|unauthorized|认证/);
    });
  });

  describe('端到端流程：边界情况', () => {
    it('应该接受秒级时间戳', async () => {
      const requestBody = createValidRequest('lock', {
        ts: Math.floor(Date.now() / 1000), // 秒级时间戳
      });
      const request = createPostRequest(requestBody);

      const response = await app.handle(request, mockEnv, mockCtx);

      // 不应该因为时间戳格式失败
      if (response.status >= 400) {
        const data = (await response.json()) as any;
        if (!data.ok) {
          expect(data.error.toLowerCase()).not.toMatch(/timestamp|时间戳/);
        }
      }
    });

    it('应该接受毫秒级时间戳', async () => {
      const requestBody = createValidRequest('lock', {
        ts: Date.now(), // 毫秒级时间戳
      });
      const request = createPostRequest(requestBody);

      const response = await app.handle(request, mockEnv, mockCtx);

      // 不应该因为时间戳格式失败
      if (response.status >= 400) {
        const data = (await response.json()) as any;
        if (!data.ok) {
          expect(data.error.toLowerCase()).not.toMatch(/timestamp|时间戳/);
        }
      }
    });

    it('应该拒绝非 JSON 请求体', async () => {
      const request = new Request('http://localhost/api/command', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: 'invalid json',
      });

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.status).toBeGreaterThanOrEqual(400);
      const data = (await response.json()) as any;
      expect(data.ok).toBe(false);
    });

    it('应该拒绝空请求体', async () => {
      const request = new Request('http://localhost/api/command', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: '',
      });

      const response = await app.handle(request, mockEnv, mockCtx);

      expect(response.status).toBeGreaterThanOrEqual(400);
      const data = (await response.json()) as any;
      expect(data.ok).toBe(false);
    });
  });
});
