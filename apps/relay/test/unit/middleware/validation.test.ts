/**
 * ValidationMiddleware 单元测试
 *
 * 测试 validationMiddleware 对所有命令和边界情况的验证
 */

import { authMiddleware } from '../../../src/infrastructure/middleware';
import type { MiddlewareContext } from '../../../src/infrastructure/middleware/types';
import { Logger } from '../../../src/infrastructure/logger';
import { CommandRequest } from '../../../src/types';

const validationMiddleware = authMiddleware;

describe('validationMiddleware', () => {
  // 恢复真实的 Date.now() 以避免时间戳验证失败
  beforeEach(() => {
    jest.restoreAllMocks();
  });
  const createContext = (body: any, apiKey: string = 'test-api-key'): MiddlewareContext => {
    const request = new Request('http://localhost/test', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

    return {
      request,
      env: { API_KEY: apiKey, CICADA_SESSIONS: {} as any },
      requestId: 'test-req-id',
      logger: new Logger({ enableConsole: false }),
      timestamp: Date.now(),
      url: new URL('http://localhost/test'),
      method: 'POST',
      headers: {},
    };
  };

  const createValidRequest = (
    cmd: string,
    overrides: Partial<CommandRequest> = {}
  ): CommandRequest => {
    return {
      device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
      cmd,
      ts: Date.now(), // 使用毫秒级时间戳（Shared 包验证器期望）
      api_key: 'test-api-key',
      ...overrides,
    };
  };

  describe('支持的命令验证', () => {
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

    test.each(supportedCommands)('应该接受支持的命令: %s', async cmd => {
      const middleware = validationMiddleware();
      const context = createContext(createValidRequest(cmd));

      let nextCalled = false;
      const result = await middleware(context, async () => {
        nextCalled = true;
        return { continue: true };
      });

      expect(nextCalled).toBe(true);
      expect(result).toEqual({ continue: true });
      expect(context.validatedRequest).toBeDefined();
      expect(context.validatedRequest?.cmd).toBe(cmd);
      expect(context.deviceId).toBe('MAC_1234567890ABCDEF1234567890ABCDEF');
    });
  });

  describe('不支持的命令验证', () => {
    const unsupportedCommands = ['bt_on', 'bt_off', 'invalid_command', 'shutdown', 'restart'];

    test.each(unsupportedCommands)('应该拒绝不支持的命令: %s', async cmd => {
      const middleware = validationMiddleware();
      const context = createContext(createValidRequest(cmd));

      const result = await middleware(context, async () => {
        throw new Error('Next should not be called');
      });

      expect(result).toHaveProperty('continue', false);
      expect(result).toHaveProperty('response');

      const response = (result as any).response as Response;
      expect(response.status).toBe(400);

      const body = (await response.json()) as any;
      expect(body.ok).toBe(false);
      expect(body.error).toBe('INVALID_COMMAND_REQUEST');
    });
  });

  describe('API Key 验证', () => {
    test('应该接受正确的 API Key', async () => {
      const middleware = validationMiddleware();
      const context = createContext(createValidRequest('ping'), 'test-api-key');

      let nextCalled = false;
      await middleware(context, async () => {
        nextCalled = true;
        return { continue: true };
      });

      expect(nextCalled).toBe(true);
    });

    test('应该拒绝错误的 API Key', async () => {
      const middleware = validationMiddleware();
      const request = createValidRequest('ping');
      request.api_key = 'wrong-key';
      const context = createContext(request, 'correct-key');

      const result = await middleware(context, async () => {
        throw new Error('Next should not be called');
      });

      expect(result).toHaveProperty('continue', false);
      const response = (result as any).response as Response;
      expect(response.status).toBe(401);
    });

    test('应该拒绝缺少 API Key 的请求', async () => {
      const middleware = validationMiddleware();
      const request = createValidRequest('ping');
      delete (request as any).api_key;
      const context = createContext(request);

      const result = await middleware(context, async () => {
        throw new Error('Next should not be called');
      });

      expect(result).toHaveProperty('continue', false);
      const response = (result as any).response as Response;
      expect(response.status).toBe(401);
    });
  });

  describe('Device ID 验证', () => {
    test('应该接受有效的 Device ID (MAC_ 前缀)', async () => {
      const middleware = validationMiddleware();
      const context = createContext(
        createValidRequest('ping', {
          device_id: 'MAC_ABCDEF1234567890ABCDEF1234567890',
        })
      );

      let nextCalled = false;
      await middleware(context, async () => {
        nextCalled = true;
        return { continue: true };
      });

      expect(nextCalled).toBe(true);
    });

    test('应该拒绝无效的 Device ID (格式错误)', async () => {
      const middleware = validationMiddleware();
      const context = createContext(
        createValidRequest('ping', {
          device_id: 'INVALID_ID',
        })
      );

      const result = await middleware(context, async () => {
        throw new Error('Next should not be called');
      });

      expect(result).toHaveProperty('continue', false);
      const response = (result as any).response as Response;
      expect(response.status).toBe(400);
    });

    test('应该拒绝缺少 Device ID 的请求', async () => {
      const middleware = validationMiddleware();
      const request = createValidRequest('ping');
      delete (request as any).device_id;
      const context = createContext(request);

      const result = await middleware(context, async () => {
        throw new Error('Next should not be called');
      });

      expect(result).toHaveProperty('continue', false);
      const response = (result as any).response as Response;
      expect(response.status).toBe(401);
    });
  });

  describe('时间戳验证', () => {
    test('应该接受当前时间戳', async () => {
      const middleware = validationMiddleware();
      const context = createContext(
        createValidRequest('ping', {
          ts: Date.now(), // 毫秒级时间戳
        })
      );

      let nextCalled = false;
      await middleware(context, async () => {
        nextCalled = true;
        return { continue: true };
      });

      expect(nextCalled).toBe(true);
    });

    test('应该接受 5 分钟内的时间戳', async () => {
      const middleware = validationMiddleware();
      const context = createContext(
        createValidRequest('ping', {
          ts: Date.now() - 4 * 60 * 1000, // 4 分钟前（毫秒）
        })
      );

      let nextCalled = false;
      await middleware(context, async () => {
        nextCalled = true;
        return { continue: true };
      });

      expect(nextCalled).toBe(true);
    });

    test('应该拒绝过期的时间戳 (超过 5 分钟)', async () => {
      const middleware = validationMiddleware();
      const context = createContext(
        createValidRequest('ping', {
          ts: Date.now() - 6 * 60 * 1000, // 6 分钟前（毫秒）
        })
      );

      const result = await middleware(context, async () => {
        throw new Error('Next should not be called');
      });

      expect(result).toHaveProperty('continue', false);
      const response = (result as any).response as Response;
      expect(response.status).toBe(400);
    });

    test('应该拒绝未来的时间戳 (超过 5 分钟)', async () => {
      const middleware = validationMiddleware();
      const context = createContext(
        createValidRequest('ping', {
          ts: Date.now() + 6 * 60 * 1000, // 6 分钟后（毫秒）
        })
      );

      const result = await middleware(context, async () => {
        throw new Error('Next should not be called');
      });

      expect(result).toHaveProperty('continue', false);
      const response = (result as any).response as Response;
      expect(response.status).toBe(400);
    });

    test('应该拒绝缺少时间戳的请求', async () => {
      const middleware = validationMiddleware();
      const request = createValidRequest('ping');
      delete (request as any).ts;
      const context = createContext(request);

      const result = await middleware(context, async () => {
        throw new Error('Next should not be called');
      });

      expect(result).toHaveProperty('continue', false);
      const response = (result as any).response as Response;
      expect(response.status).toBe(401);
    });
  });

  describe('命令参数验证', () => {
    test('应该接受带有有效参数的命令', async () => {
      const middleware = validationMiddleware();
      const context = createContext(
        createValidRequest('caffeinate', {
          params: { duration: 3600 },
        })
      );

      let nextCalled = false;
      await middleware(context, async () => {
        nextCalled = true;
        return { continue: true };
      });

      expect(nextCalled).toBe(true);
    });

    test('应该接受不带参数的命令', async () => {
      const middleware = validationMiddleware();
      const context = createContext(createValidRequest('lock'));

      let nextCalled = false;
      await middleware(context, async () => {
        nextCalled = true;
        return { continue: true };
      });

      expect(nextCalled).toBe(true);
    });
  });

  describe('边界情况', () => {
    test('应该拒绝非 JSON 请求体', async () => {
      const middleware = validationMiddleware();
      const request = new Request('http://localhost/test', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: 'invalid json',
      });

      const context: MiddlewareContext = {
        request,
        env: { API_KEY: 'test-key', CICADA_SESSIONS: {} as any },
        requestId: 'test-req-id',
        logger: new Logger({ enableConsole: false }),
        timestamp: Date.now(),
        url: new URL('http://localhost/test'),
        method: 'POST',
        headers: {},
      };

      const result = await middleware(context, async () => {
        throw new Error('Next should not be called');
      });

      expect(result).toHaveProperty('continue', false);
      const response = (result as any).response as Response;
      expect(response.status).toBe(400);
    });

    test('应该跳过非 POST 请求的验证', async () => {
      const middleware = validationMiddleware();
      const request = new Request('http://localhost/test', {
        method: 'GET',
      });

      const context: MiddlewareContext = {
        request,
        env: { API_KEY: 'test-key', CICADA_SESSIONS: {} as any },
        requestId: 'test-req-id',
        logger: new Logger({ enableConsole: false }),
        timestamp: Date.now(),
        url: new URL('http://localhost/test'),
        method: 'GET',
        headers: {},
      };

      let nextCalled = false;
      const result = await middleware(context, async () => {
        nextCalled = true;
        return { continue: true };
      });

      expect(nextCalled).toBe(true);
      expect(result).toEqual({ continue: true });
    });

    test('应该拒绝空请求体', async () => {
      const middleware = validationMiddleware();
      const context = createContext({});

      const result = await middleware(context, async () => {
        throw new Error('Next should not be called');
      });

      expect(result).toHaveProperty('continue', false);
      const response = (result as any).response as Response;
      expect(response.status).toBe(401);
    });

    test('应该拒绝 null 请求体', async () => {
      const middleware = validationMiddleware();
      const context = createContext(null);

      const result = await middleware(context, async () => {
        throw new Error('Next should not be called');
      });

      expect(result).toHaveProperty('continue', false);
      const response = (result as any).response as Response;
      expect(response.status).toBe(400);
    });
  });
});
