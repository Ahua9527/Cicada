/**
 * Jest 测试设置文件
 */

// 设置测试环境变量
process.env.NODE_ENV = 'test';
process.env.API_KEY = 'test-api-key-for-testing-only';

// 模拟 Web Crypto API
Object.defineProperty(global, 'crypto', {
  value: {
    subtle: {
      importKey: jest.fn(),
      sign: jest.fn(),
      verify: jest.fn(),
      digest: jest.fn(),
    },
    getRandomValues: jest.fn((array: Uint8Array) => {
      for (let i = 0; i < array.length; i += 1) {
        array[i] = Math.floor(Math.random() * 256);
      }
      return array;
    }),
  },
});

// 模拟 WebSocket
global.WebSocket = jest.fn().mockImplementation(() => ({
  addEventListener: jest.fn(),
  send: jest.fn(),
  close: jest.fn(),
  readyState: 1, // WebSocket.OPEN
})) as any;

Object.defineProperty(global, 'WebSocketPair', {
  value: jest.fn().mockImplementation(() => {
    const mockWebSocket = {
      accept: jest.fn(),
      addEventListener: jest.fn(),
      send: jest.fn(),
      close: jest.fn(),
      readyState: 1,
    };

    return {
      0: mockWebSocket, // client
      1: mockWebSocket, // server
    };
  }),
});

// 模拟 DurableObject
class MockDurableObjectState {
  storage = new Map();

  blockConcurrencyWhile = jest.fn(fn => fn());

  async get(key: string) {
    return this.storage.get(key);
  }

  async put(key: string, value: any) {
    this.storage.set(key, value);
  }

  async delete(key: string) {
    this.storage.delete(key);
  }

  async list() {
    return Array.from(this.storage.entries());
  }
}

class MockDurableObjectNamespace {
  idFromName(name: string) {
    return { name };
  }

  async get(_id: any) {
    return new MockDurableObjectService();
  }
}

class MockDurableObjectService {
  async fetch(_url: string, _options?: RequestInit) {
    return new Response(JSON.stringify({ success: true }));
  }
}

// 模拟 Cloudflare Workers 环境
(global as any).DurableObjectState = MockDurableObjectState;
(global as any).DurableObjectNamespace = MockDurableObjectNamespace;

// 创建模拟的环境变量
const mockEnv = {
  API_KEY: 'test-api-key-for-testing-only',
  NODE_ENV: 'test',
  CICADA_SESSIONS: new MockDurableObjectNamespace(),
};
(global as any).mockEnv = mockEnv;

// 设置全局超时
jest.setTimeout(10000);

// 全局测试工具函数
(global as any).createMockRequest = (overrides: Partial<Request> = {}) => {
  const defaultRequest = {
    url: 'https://cicada-relay.example.com/test',
    method: 'GET',
    headers: new Headers({
      'Content-Type': 'application/json',
      'User-Agent': 'test-agent',
    }),
    json: () => Promise.resolve({}),
    text: () => Promise.resolve('test'),
    arrayBuffer: () => Promise.resolve(new ArrayBuffer(0)),
  };

  return { ...defaultRequest, ...overrides };
};

(global as any).createMockEnv = (overrides: Partial<any> = {}) => {
  return {
    ...mockEnv,
    ...overrides,
  };
};

// 控制台输出设置
const originalConsoleError = console.error;
console.error = (...args: any[]) => {
  // 在测试中减少错误输出噪音
  if (typeof args[0] === 'string' && args[0].includes('deprecated')) {
    return;
  }
  originalConsoleError(...args);
};

// 清理函数
afterEach(() => {
  jest.clearAllMocks();
});

// 模拟时间函数
beforeEach(() => {
  const mockDate = new Date('2024-01-01T00:00:00.000Z');
  jest.spyOn(Date.prototype, 'getTime').mockReturnValue(mockDate.getTime());
  jest.spyOn(Date, 'now').mockReturnValue(mockDate.getTime());
});

// 创建有效请求的辅助函数（使用 API Key 认证）
(global as any).createValidRequest = async (overrides: Partial<any> = {}) => {
  const defaultRequest = {
    device_id: 'MAC_1234567890ABCDEF1234567890ABCDEF',
    cmd: 'lock',
    ts: Math.floor(Date.now() / 1000),
    api_key: 'test-api-key-for-testing-only',
  };

  return { ...defaultRequest, ...overrides };
};
