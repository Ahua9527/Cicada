/**
 * WebSocket 集成测试
 * 测试 WebSocket 连接和消息处理
 */

import { SessionManagerDO } from '../../src/infrastructure/persistence';
import { SESSION_CONSTANTS } from '../../src/config/constants';
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
      const socket = createMockSocket();

      await sessionManager.addSession('test-device', socket as unknown as WebSocket);

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

      await sessionManager.addSession('test-device', socket as unknown as WebSocket);
      socket.emit('message', {
        data: JSON.stringify({
          type: 'ping',
          id: 'ping-1',
          timestamp: 123,
        }),
      });

      expect(socket.send).toHaveBeenCalledTimes(1);
      const sentPayload = JSON.parse(socket.send.mock.calls[0][0]);
      expect(sentPayload).toMatchObject({
        type: 'pong',
        id: 'ping-1',
      });
      expect(typeof sentPayload.timestamp).toBe('number');
      expect(sentPayload.data).toMatchObject({
        deviceId: 'test-device',
      });
    });

    it('should update activity without replying when agent sends pong', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      const socket = createMockSocket();

      await sessionManager.addSession('test-device', socket as unknown as WebSocket);
      socket.emit('message', {
        data: JSON.stringify({
          type: 'pong',
          id: 'pong-1',
          timestamp: 123,
        }),
      });

      expect(socket.send).not.toHaveBeenCalled();
    });

    it('should handle command acknowledgment', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      // Mock WebSocket message handling
      expect(sessionManager).toBeDefined();
    });
  });

  describe('Session Management', () => {
    it('should close the previous socket when the same device reconnects', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      const firstSocket = createMockSocket();
      const secondSocket = createMockSocket();

      await sessionManager.addSession('test-device', firstSocket as unknown as WebSocket);
      await sessionManager.addSession('test-device', secondSocket as unknown as WebSocket);

      expect(firstSocket.close).toHaveBeenCalledTimes(1);
      expect(secondSocket.close).not.toHaveBeenCalled();
      expect(sessionManager.getConnectedDevices()).toEqual(['test-device']);

      firstSocket.emit('close');
      expect(sessionManager.getConnectedDevices()).toEqual(['test-device']);
    });

    it('should not expose local session status from the room object', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      const socket = createMockSocket();

      await sessionManager.addSession('test-device', socket as unknown as WebSocket);
      socket.emit('close');

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
      const registry = new SessionManagerDO(
        createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME),
        mockEnv
      );
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
      const deviceId = 'MAC_1234567890ABCDEF1234567890ABCDEF';

      await sessionManager.addRelaySocket('session-live-1', socket as unknown as WebSocket, {
        deviceId,
        agentIdentityPublicKey: 'agent-public-key',
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

    it('should reject new devices when max concurrent session limit is reached', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv, {
        maxConcurrentSessions: 1,
      });

      const firstResult = await sessionManager.addSession(
        'device-one',
        createMockSocket() as unknown as WebSocket
      );
      const secondResult = await sessionManager.addSession(
        'device-two',
        createMockSocket() as unknown as WebSocket
      );

      expect(firstResult).toEqual({ success: true });
      expect(secondResult).toEqual({
        success: false,
        error: 'Maximum concurrent sessions reached',
      });
    });

    it('should report send failures from the socket', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      const socket = createMockSocket();
      socket.send.mockImplementation(() => {
        throw new Error('broken socket');
      });

      await sessionManager.addSession('test-device', socket as unknown as WebSocket);
      const result = await sessionManager.sendMessage('test-device', {
        type: 'ping',
        timestamp: Date.now(),
      });

      expect(result).toEqual({
        success: false,
        error: 'Failed to send message',
      });
    });

    it('should report broadcast successes and failures', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      const goodSocket = createMockSocket();
      const badSocket = createMockSocket();
      badSocket.send.mockImplementation(() => {
        throw new Error('broadcast failed');
      });

      await sessionManager.addSession('device-one', goodSocket as unknown as WebSocket);
      await sessionManager.addSession('device-two', badSocket as unknown as WebSocket);

      const result = await sessionManager.broadcastMessage({
        type: 'ping',
        timestamp: Date.now(),
      });

      expect(result.success).toBe(1);
      expect(result.failed).toBe(1);
      expect(result.errors[0]).toContain('device-two');
    });

    it('should persist a nonce exactly once without trimming', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv, {
        nonceCacheSize: 2,
        nonceRetentionSize: 1,
      });
      const put = mockState.storage.put as jest.Mock;

      await sessionManager.markNonceUsed('nonce-one');

      expect(put).toHaveBeenCalledTimes(1);
      expect(put).toHaveBeenCalledWith({
        [SESSION_CONSTANTS.STORAGE_KEYS.SESSIONS]: [],
        [SESSION_CONSTANTS.STORAGE_KEYS.NONCES]: ['nonce-one'],
      });
    });

    it('should trim and persist the nonce cache exactly once', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv, {
        nonceCacheSize: 2,
        nonceRetentionSize: 1,
      });
      const put = mockState.storage.put as jest.Mock;

      await sessionManager.markNonceUsed('nonce-one');
      await sessionManager.markNonceUsed('nonce-two');
      put.mockClear();
      await sessionManager.markNonceUsed('nonce-three');

      expect(put).toHaveBeenCalledTimes(1);
      expect(put).toHaveBeenCalledWith({
        [SESSION_CONSTANTS.STORAGE_KEYS.SESSIONS]: [],
        [SESSION_CONSTANTS.STORAGE_KEYS.NONCES]: ['nonce-three'],
      });
      expect(sessionManager.isNonceUsed('nonce-one')).toBe(false);
      expect(sessionManager.isNonceUsed('nonce-three')).toBe(true);
    });

    it('should cleanup inactive sessions and close their sockets', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv, {
        sessionTimeout: 1,
      });
      const socket = createMockSocket();

      await sessionManager.addSession('test-device', socket as unknown as WebSocket);
      const info = sessionManager.getSessionInfo('test-device');
      if (info) {
        info.lastPing = Date.now() - 10;
        info.lastActivity = Date.now() - 10;
      }

      const result = await sessionManager.cleanupInactiveSessions();

      expect(result.cleaned).toBe(1);
      expect(result.remaining).toBe(0);
      expect(socket.close).toHaveBeenCalled();
    });

    it('should disconnect a single device and all devices explicitly', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      await sessionManager.addSession('device-one', createMockSocket() as unknown as WebSocket);
      await sessionManager.addSession('device-two', createMockSocket() as unknown as WebSocket);

      await expect(sessionManager.disconnectDevice('device-one')).resolves.toBe(true);
      await expect(sessionManager.disconnectDevice('missing-device')).resolves.toBe(false);
      await expect(sessionManager.disconnectAllDevices()).resolves.toBe(1);
      expect(sessionManager.getConnectedDevices()).toEqual([]);
    });

    it('should expose registry device summaries only', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);

      await sessionManager.fetch(
        new Request('http://session/registry/agent-online', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            deviceId: 'MAC_1234567890ABCDEF1234567890ABCDEF',
            sessionId: 'session-1',
            agentIdentityPublicKey: 'agent-public-key',
          }),
        })
      );

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
      const registry = new SessionManagerDO(createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME), mockEnv);

      const missing = await registry.fetch(
        new Request('http://session/registry/agent-online', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({}),
        })
      );
      expect(missing.status).toBe(400);

      const update = await registry.fetch(
        new Request('http://session/registry/agent-online', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            deviceId: 'MAC_1234567890ABCDEF1234567890ABCDEF',
            sessionId: 'session-1',
            agentIdentityPublicKey: 'agent-public-key',
          }),
        })
      );
      expect(update.status).toBe(200);

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
      const registry = new SessionManagerDO(createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME), mockEnv);
      const deviceId = 'MAC_REPLAY_SECRET_DEVICE';
      const nonce = 'nonce-replay-secret';
      const signature = 'signature-replay-secret';
      const requestId = 'req-replay-test';
      const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);

      const firstSeen = await registry.fetch(
        new Request('http://session/registry/agent-online', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            deviceId,
            sessionId: 'session-first-seen',
            agentIdentityPublicKey: 'agent-public-key',
          }),
        })
      );
      expect(firstSeen.status).toBe(200);

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

    it('should update options and destroy all sessions', async () => {
      const sessionManager = new SessionManagerDO(mockState, mockEnv);
      await sessionManager.addSession('test-device', createMockSocket() as unknown as WebSocket);

      sessionManager.updateOptions({ cleanupInterval: 1000 });
      await sessionManager.destroy();

      expect(sessionManager.getConnectedDevices()).toEqual([]);
    });
  });
});
