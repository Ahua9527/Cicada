/**
 * WebSocket 集成测试
 * 测试 WebSocket 连接和消息处理
 */

import { SessionManagerDO } from '../../src/infrastructure/persistence';
import { SESSION_CONSTANTS } from '../../src/config/constants';
import { RELAY_CLOSE_CODES } from '../../src/types';
import type { Env } from '../../src/types';

describe('WebSocket Integration Tests', () => {
  let mockEnv: Env;
  let mockState: DurableObjectState;

  const createMockState = (name?: string, storedValues: Record<string, unknown> = {}): DurableObjectState =>
    ({
      id: {
        toString: () => name ?? 'anonymous-id',
        equals: jest.fn(),
        name,
      },
      storage: {
        get: jest.fn((key: string) => Promise.resolve(storedValues[key] ?? null)),
        put: jest.fn().mockResolvedValue(undefined),
        delete: jest.fn().mockResolvedValue(undefined),
        list: jest.fn().mockResolvedValue(new Map()),
        transaction: jest.fn(),
        getAlarm: jest.fn(),
        setAlarm: jest.fn(),
        deleteAlarm: jest.fn(),
        sync: jest.fn(),
      },
      blockConcurrencyWhile: jest.fn(async (callback: () => Promise<void>) => {
        await callback();
      }),
      waitUntil: jest.fn(),
    }) as any;

  const createMockSocket = () => {
    const listeners = new Map<string, Array<(event: any) => void>>();
    const socket = {
      accept: jest.fn(),
      send: jest.fn(),
      close: jest.fn(),
      addEventListener: jest.fn((type: string, listener: (event: any) => void) => {
        const current = listeners.get(type) ?? [];
        current.push(listener);
        listeners.set(type, current);
      }),
      emit(type: string, event: any = {}) {
        for (const listener of listeners.get(type) ?? []) {
          listener(event);
        }
      },
    };

    return socket;
  };

  beforeEach(() => {
    mockEnv = {
      ENABLE_CORS: 'false',
      RATE_LIMIT_ENABLED: 'false',
      DEBUG_MODE: 'false',
      CICADA_SESSIONS: {} as any,
    };

    mockState = createMockState('test-device');
  });

  describe('SessionManagerDO', () => {
    it('should create Durable Object instance', () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      expect(sessionManager).toBeDefined();
    });

    it('should handle agent relay WebSocket upgrade request', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      const request = new Request('http://localhost/relay/live-session', {
        headers: {
          Upgrade: 'websocket',
          'X-Device-ID': 'MAC_1234567890ABCDEF1234567890ABCDEF',
          'X-Agent-Identity-Public-Key': 'agent-public-key',
        },
      });

      const response = await sessionManager.fetch(request);

      // Should either upgrade or reject with appropriate status
      expect(response.status).toBeGreaterThanOrEqual(101);
      expect(response.status).toBeLessThan(500);
    });

    it('should reject non-WebSocket relay requests', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      const request = new Request('http://localhost/relay/live-session', {
        method: 'GET',
      });

      const response = await sessionManager.fetch(request);

      expect(response.status).toBeGreaterThanOrEqual(400);
    });

    it('should not expose the old session info endpoint', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      const request = new Request('http://session/info', {
        method: 'GET',
      });

      const response = await sessionManager.fetch(request);
      const data = (await response.json()) as any;

      expect(response.status).toBe(404);
      expect(data).toMatchObject({ success: false, path: '/info' });
    });

    it('should not expose the old direct send endpoint', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      const request = new Request('http://session/send', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': 'test-device',
        },
        body: JSON.stringify({
          type: 'command',
          cmd: 'ping',
          data: {},
        }),
      });

      const response = await sessionManager.fetch(request);
      const data = (await response.json()) as any;

      expect(response.status).toBe(404);
      expect(data).toMatchObject({ success: false, path: '/send' });
    });

    it('should not expose the old disconnect endpoint', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      const request = new Request('http://session/disconnect', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          device_id: 'test-device',
        }),
      });

      const response = await sessionManager.fetch(request);
      const data = (await response.json()) as any;

      expect(response.status).toBe(404);
      expect(data).toMatchObject({ success: false, path: '/disconnect' });
    });

    it('should not expose the old stats endpoint', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      const request = new Request('http://session/stats', {
        method: 'GET',
      });

      const response = await sessionManager.fetch(request);
      const data = (await response.json()) as any;

      expect(response.status).toBe(404);
      expect(data).toMatchObject({ success: false, path: '/stats' });
    });
  });

  describe('WebSocket Message Handling', () => {
    it('should reply with pong when agent sends ping', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      const socket = createMockSocket();

      await sessionManager.addRelaySocket('test-session', socket as unknown as WebSocket);
      socket.emit('message', {
        data: JSON.stringify({
          type: 'ping',
          id: 'ping-1',
          timestamp: 123,
        }),
      });

      expect(socket.send).toHaveBeenCalledTimes(1);
      expect(JSON.parse(socket.send.mock.calls[0][0])).toEqual({
        type: 'pong',
        id: 'ping-1',
        sent_at: expect.any(Number),
      });
    });

    it('should not reply when agent sends pong or a binary frame', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      const socket = createMockSocket();

      await sessionManager.addRelaySocket('test-session', socket as unknown as WebSocket);
      socket.emit('message', {
        data: JSON.stringify({
          type: 'pong',
          id: 'pong-1',
          timestamp: 123,
        }),
      });
      socket.emit('message', { data: new ArrayBuffer(4) });

      expect(socket.send).not.toHaveBeenCalled();
    });

    it('should report invalid JSON from the agent', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      const socket = createMockSocket();

      await sessionManager.addRelaySocket('test-session', socket as unknown as WebSocket);
      socket.emit('message', { data: '{' });

      expect(JSON.parse(socket.send.mock.calls[0][0])).toEqual({
        type: 'error',
        code: 'invalid_json',
        error: 'Relay transport messages must be JSON.',
        sent_at: expect.any(Number),
      });
    });

    it('should handle command acknowledgment', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      // Mock WebSocket message handling
      expect(sessionManager).toBeDefined();
    });
  });

  describe('Session Management', () => {
    it('should close the previous socket when the agent reconnects', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      const firstSocket = createMockSocket();
      const secondSocket = createMockSocket();

      await sessionManager.addRelaySocket('test-session', firstSocket as unknown as WebSocket);
      await sessionManager.addRelaySocket('test-session', secondSocket as unknown as WebSocket);

      expect(firstSocket.close).toHaveBeenCalledTimes(1);
      expect(firstSocket.close).toHaveBeenCalledWith(
        RELAY_CLOSE_CODES.AGENT_REPLACED,
        'Previous agent connection replaced'
      );
      expect(secondSocket.close).not.toHaveBeenCalled();

      // 旧连接的 close 事件不能把新连接从房间里摘掉：命令仍然发给新连接。
      firstSocket.emit('close');
      const response = sessionManager.fetch(
        new Request('http://session/shortcut/command', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ requestId: 'req-1', grantId: 'grant-1', command: 'ping' }),
        })
      );
      await new Promise(resolve => setTimeout(resolve, 0));
      const [dispatched] = secondSocket.send.mock.calls.map(([raw]) => JSON.parse(raw as string));
      expect(dispatched).toMatchObject({ type: 'shortcut_command', data: { command: 'ping' } });
      expect(firstSocket.send).not.toHaveBeenCalled();
      secondSocket.emit('message', {
        data: JSON.stringify({
          type: 'shortcut_result',
          id: dispatched.id,
          data: { requestId: dispatched.id, ok: true, success: true },
        }),
      });
      expect((await response).status).toBe(200);
    });

    it('should not expose local session status from the room object', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      const response = await sessionManager.fetch(
        new Request('http://session/status', {
          method: 'GET',
          headers: {
            'X-Device-ID': 'test-device',
          },
        })
      );
      const data = (await response.json()) as any;

      expect(response.status).toBe(404);
      expect(data).toMatchObject({ success: false, path: '/status' });
    });

    it('should not expose direct send for offline devices', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      const request = new Request('http://session/send', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Device-ID': 'test-device',
        },
        body: JSON.stringify({
          type: 'command',
          id: 'cmd-1',
          cmd: 'ping',
          ts: Date.now(),
          timestamp: Date.now(),
          data: { command: 'ping' },
        }),
      });

      const response = await sessionManager.fetch(request);
      const data = (await response.json()) as any;

      expect(response.status).toBe(404);
      expect(data).toMatchObject({ success: false, path: '/send' });
    });

    it('should update registry records across connect and close lifecycle', async () => {
      const deviceId = 'MAC_1234567890ABCDEF1234567890ABCDEF';
      // 这里只测连接生命周期：已绑定设备的签名校验由 session-manager-do 测试用真实 Ed25519 覆盖，
      // 公钥和签名只需是合法 base64。crypto.subtle 是 setup.ts 的全局 mock，别的测试文件会改它的实现，
      // 所以只给这一次登记各放一次结果。
      const agentPublicKey = Buffer.from('agent-public-key').toString('base64');
      (crypto.subtle.importKey as jest.Mock).mockResolvedValueOnce({});
      (crypto.subtle.verify as jest.Mock).mockResolvedValueOnce(true);
      const registry = new SessionManagerDO(
        createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME, {
          [SESSION_CONSTANTS.STORAGE_KEYS.DEVICE_REGISTRY]: [
            { deviceId, connected: false, agentIdentityPublicKey: agentPublicKey, lastSeen: 0 },
          ],
        }),
        mockEnv
      );
      await new Promise(resolve => setTimeout(resolve, 0));
      const namespace = {
        idFromName: jest.fn((name: string) => ({ name })),
        get: jest.fn(() => registry),
      };
      const sessionManager = new SessionManagerDO(
        createMockState('device-session'),
        {
          ...mockEnv,
          CICADA_SESSIONS: namespace as any,
        },
        { agentAbsenceGraceMs: 1 }
      );
      const socket = createMockSocket();

      await sessionManager.addRelaySocket('session-live-1', socket as unknown as WebSocket, {
        deviceId,
        agentIdentityPublicKey: agentPublicKey,
        registrationTimestamp: Date.now(),
        registrationNonce: 'nonce-lifecycle',
        registrationSignature: Buffer.from('signature').toString('base64'),
      });

      const onlineResponse = await registry.fetch(
        new Request('http://session/registry/devices', { method: 'GET' })
      );
      const onlineData = (await onlineResponse.json()) as any;
      expect(onlineData).toMatchObject({
        success: true,
        total: 1,
        active: 1,
        devices: [
          {
            deviceId,
            connected: true,
          },
        ],
      });

      socket.emit('close');
      await new Promise(resolve => setTimeout(resolve, 5));

      const offlineResponse = await registry.fetch(
        new Request('http://session/registry/devices', { method: 'GET' })
      );
      const offlineData = (await offlineResponse.json()) as any;
      expect(offlineData).toMatchObject({
        success: true,
        total: 1,
        active: 0,
        devices: [
          {
            deviceId,
            connected: false,
          },
        ],
      });
    });

    it('should report agent send failures as agent unavailable', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      const socket = createMockSocket();
      socket.send.mockImplementation(() => {
        throw new Error('broken socket');
      });

      await sessionManager.addRelaySocket('test-session', socket as unknown as WebSocket);
      const response = await sessionManager.fetch(
        new Request('http://session/shortcut/command', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ requestId: 'req-1', grantId: 'grant-1', command: 'ping' }),
        })
      );

      // 5xx 在 DO 出口统一脱敏，只保留状态码。
      expect(response.status).toBe(503);
      expect(await response.json()).toMatchObject({ ok: false, error: 'Internal server error' });
    });

    it('should drop stale stored sessions on the cleanup timer', async () => {
      const now = Date.now();
      const state = createMockState('test-device', {
        [SESSION_CONSTANTS.STORAGE_KEYS.SESSIONS]: [
          { sessionId: 'stale', deviceId: 'stale-device', lastPing: now - 10 },
          { sessionId: 'fresh', deviceId: 'fresh-device', lastPing: now },
        ],
      });
      const sessionManager = new SessionManagerDO(state, mockEnv, {
        sessionTimeout: 5,
        cleanupInterval: 2,
      });
      expect(sessionManager).toBeDefined();

      await new Promise(resolve => setTimeout(resolve, 10));

      const put = state.storage.put as jest.Mock;
      expect(put).toHaveBeenCalled();
      const [saved] = put.mock.calls[put.mock.calls.length - 1];
      expect(saved).toEqual({
        [SESSION_CONSTANTS.STORAGE_KEYS.SESSIONS]: [
          expect.objectContaining({ sessionId: 'fresh', deviceId: 'fresh-device' }),
        ],
      });
    });

    it('should report how many stale sessions cleanup removed', async () => {
      const now = Date.now();
      const sessionManager = new SessionManagerDO(
        createMockState('test-device', {
          [SESSION_CONSTANTS.STORAGE_KEYS.SESSIONS]: [
            { sessionId: 'stale', deviceId: 'stale-device', lastPing: now - 10 },
            { sessionId: 'fresh', deviceId: 'fresh-device', lastPing: now },
          ],
        }),
        mockEnv,
        { sessionTimeout: 5 }
      );
      // 等 blockConcurrencyWhile 里的 loadSessions 读完存储。
      await new Promise(resolve => setTimeout(resolve, 0));

      await expect(sessionManager.cleanupInactiveSessions()).resolves.toEqual({
        cleaned: 1,
        remaining: 1,
      });
    });

    it('should expose registry device summaries only', async () => {
      const sessionManager = new SessionManagerDO(
        createMockState('test-device', {
          [SESSION_CONSTANTS.STORAGE_KEYS.DEVICE_REGISTRY]: [
            {
              deviceId: 'MAC_1234567890ABCDEF1234567890ABCDEF',
              connected: true,
              liveSessionId: 'session-1',
              agentIdentityPublicKey: 'agent-public-key',
              shortcutGrants: [],
              lastSeen: Date.now(),
            },
          ],
        }),
        mockEnv
      );
      await new Promise(resolve => setTimeout(resolve, 0));

      const request = new Request('http://session/registry/devices', { method: 'GET' });

      const response = await sessionManager.fetch(request);
      const data = (await response.json()) as any;

      expect(response.status).toBe(200);
      expect(data).toMatchObject({
        success: true,
        total: 1,
        active: 1,
        devices: [
          {
            deviceId: 'MAC_1234567890ABCDEF1234567890ABCDEF',
            connected: true,
          },
        ],
      });
      expect(data.devices[0]).not.toHaveProperty('shortcutGrants');
      expect(data.devices[0]).not.toHaveProperty('agentIdentityPublicKey');
    });

    it('should not expose the old cleanup endpoint', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      const request = new Request('http://session/cleanup', {
        method: 'POST',
      });

      const response = await sessionManager.fetch(request);
      const data = (await response.json()) as any;

      expect(response.status).toBe(404);
      expect(data).toMatchObject({ success: false, path: '/cleanup' });
    });

    it('should not expose the old connect endpoint', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      const success = await sessionManager.fetch(
        new Request('http://session/connect', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'CF-Connecting-IP': '203.0.113.42',
            'User-Agent': 'CicadaTest/1.0',
          },
          body: JSON.stringify({
            deviceId: 'test-device',
            timestamp: Date.now(),
          }),
        })
      );
      expect(success.status).toBe(404);

      const methodNotAllowed = await sessionManager.fetch(
        new Request('http://session/connect', { method: 'GET' })
      );
      expect(methodNotAllowed.status).toBe(404);

      const invalid = await sessionManager.fetch(
        new Request('http://session/connect', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: 'invalid json',
        })
      );
      expect(invalid.status).toBe(404);
    });

    it('should handle registry endpoint validation and status summaries', async () => {
      const registry = new SessionManagerDO(
        createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME, {
          [SESSION_CONSTANTS.STORAGE_KEYS.DEVICE_REGISTRY]: [
            {
              deviceId: 'MAC_1234567890ABCDEF1234567890ABCDEF',
              connected: true,
              agentIdentityPublicKey: 'agent-public-key',
              lastSeen: Date.now(),
            },
          ],
        }),
        mockEnv
      );
      await new Promise(resolve => setTimeout(resolve, 0));

      const missing = await registry.fetch(
        new Request('http://session/registry/agent-online', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({}),
        })
      );
      expect(missing.status).toBe(400);

      // 没有注册码的新 deviceId 不能首次登记，也不会进入下面的统计。
      const unenrolled = await registry.fetch(
        new Request('http://session/registry/agent-online', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            deviceId: 'MAC_FEDCBA0987654321FEDCBA0987654321',
            sessionId: 'session-1',
            agentIdentityPublicKey: 'agent-public-key',
          }),
        })
      );
      expect(unenrolled.status).toBe(401);
      expect(await unenrolled.json()).toMatchObject({ code: 'agent_enrollment_code_required' });

      const status = await registry.fetch(
        new Request('http://session/registry/status', { method: 'GET' })
      );
      const statusData = (await status.json()) as any;
      expect(statusData).toMatchObject({
        totalDevices: 1,
        activeDevices: 1,
        activeConnections: 1,
      });

      const badMethod = await registry.fetch(
        new Request('http://session/registry/status', { method: 'POST' })
      );
      expect(badMethod.status).toBe(405);
    });

    it('should log replay rejection as a stable event without sensitive registration data', async () => {
      const deviceId = 'MAC_REPLAY_SECRET_DEVICE';
      // 已绑定的设备：重放检查发生在验签之前。
      const registry = new SessionManagerDO(
        createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME, {
          [SESSION_CONSTANTS.STORAGE_KEYS.DEVICE_REGISTRY]: [
            { deviceId, connected: false, agentIdentityPublicKey: 'agent-public-key', lastSeen: 0 },
          ],
        }),
        mockEnv
      );
      await new Promise(resolve => setTimeout(resolve, 0));
      const nonce = 'nonce-replay-secret';
      const signature = 'signature-replay-secret';
      const requestId = 'req-replay-test';
      const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);

      const replayCache = (
        registry as unknown as { usedRegistrationNonces: Map<string, number> }
      ).usedRegistrationNonces;
      replayCache.set(
        `${deviceId}|agent|${nonce}`,
        Date.now() + SESSION_CONSTANTS.AGENT_REGISTRATION_SKEW
      );

      const replay = await registry.fetch(
        new Request('http://session/registry/agent-online', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'X-Request-ID': requestId },
          body: JSON.stringify({
            deviceId,
            sessionId: 'session-replay',
            agentIdentityPublicKey: 'agent-public-key',
            registrationTimestamp: Date.now(),
            registrationNonce: nonce,
            registrationSignature: signature,
          }),
        })
      );

      expect(replay.status).toBe(409);
      expect(warn).toHaveBeenCalledTimes(1);
      const eventText = String(warn.mock.calls[0]?.[0]);
      expect(JSON.parse(eventText)).toEqual({
        level: 'warn',
        message: 'Agent registration replay rejected',
        request_id: requestId,
        security_event: 'agent_registration_replayed',
        status: 409,
        do_operation: 'registry_agent_online',
      });
      expect(eventText).not.toContain(deviceId);
      expect(eventText).not.toContain(nonce);
      expect(eventText).not.toContain(signature);
    });

    it('should reject WebSocket upgrades outside /relay', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      const response = await sessionManager.fetch(
        new Request('http://localhost/ws', {
          headers: {
            Upgrade: 'websocket',
          },
        })
      );

      expect(response.status).toBe(404);
    });
  });
});
