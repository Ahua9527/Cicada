import { readFileSync } from 'node:fs';
import { CicadaRelayApp } from '../../src/presentation/app';
import { SessionManagerDO } from '../../src/infrastructure/persistence';
import { SESSION_CONSTANTS } from '../../src/config/constants';
import type { Env } from '../../src/types';

describe('Shortcuts-only relay transport', () => {
  const token = 'cicada_sc_test_token';
  const tokenHash = Buffer.from('token-hash').toString('base64url');
  const deviceId = 'MAC_1234567890ABCDEF1234567890ABCDEF';
  const digestBytes = (value: string): ArrayBuffer => {
    const buffer = Buffer.from(value);
    return buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength);
  };

  const createMockState = (name?: string, storedValues: Record<string, unknown> = {}): DurableObjectState =>
    ({
      id: {
        toString: () => name ?? 'anonymous-id',
        equals: jest.fn(),
        name,
      },
      storage: {
        get: jest.fn((key: string) => Promise.resolve(storedValues[key] ?? null)),
        put: jest.fn((key: string, value: unknown) => {
          storedValues[key] = value;
          return Promise.resolve();
        }),
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

  const createEnv = (
    registry?: SessionManagerDO | (() => SessionManagerDO | undefined),
    rooms = new Map<string, SessionManagerDO>()
  ): Env => ({
    ENABLE_CORS: 'false',
    RATE_LIMIT_ENABLED: 'false',
    DEBUG_MODE: 'false',
    CICADA_SESSIONS: {
      idFromName: jest.fn((name: string) => ({ name })),
      get: jest.fn((id: { name: string }) => {
        const registryInstance = typeof registry === 'function' ? registry() : registry;
        if (id.name === SESSION_CONSTANTS.REGISTRY_DO_NAME && registryInstance) {
          return registryInstance;
        }
        if (!rooms.has(id.name)) {
          rooms.set(id.name, new SessionManagerDO(createMockState(id.name), {} as Env));
        }
        return rooms.get(id.name);
      }),
    } as any,
  });

  beforeEach(() => {
    (global.crypto.subtle.digest as jest.Mock).mockResolvedValue(digestBytes('token-hash'));
  });

  const loadTransportFixture = (name: string): any =>
    JSON.parse(
      readFileSync(
        new URL(`../../../../packages/shared/protocol/fixtures/${name}.json`, import.meta.url),
        'utf8'
      )
    );

  const expectKeys = (value: Record<string, unknown>, keys: string[]) => {
    expect(Object.keys(value).sort()).toEqual([...keys].sort());
  };

  const executeFixtureResult = async (result: any) => {
    const session = new SessionManagerDO(createMockState('fixture-session'), {} as Env);
    const agent = createMockSocket();
    await session.addRelaySocket('fixture-session', agent as unknown as WebSocket, {
      deviceId,
      agentIdentityPublicKey: 'fixture-public-key',
    });
    const responsePromise = session.fetch(
      new Request('http://session/shortcut/command', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          requestId: 'fixture-request-1',
          grantId: 'fixture-grant-1',
          command: 'ping',
          params: { value: 'fixture-input' },
        }),
      })
    );
    await new Promise((resolve) => setTimeout(resolve, 0));
    const command = agent.send.mock.calls
      .map(([raw]) => JSON.parse(raw as string))
      .find((message) => message.type === 'shortcut_command');
    agent.emit('message', {
      data: JSON.stringify({
        ...result,
        id: command.id,
        data: { ...result.data, requestId: command.data.requestId },
      }),
    });
    return { command, response: await responsePromise };
  };

  it('emits the shared shortcut_command wire shape', async () => {
    const fixture = loadTransportFixture('shortcut_command');
    const { command, response } = await executeFixtureResult(
      loadTransportFixture('shortcut_result_success')
    );
    expect(response.status).toBe(200);
    expect(command.id).toEqual(expect.any(String));
    expect(command.id).not.toBe('fixture-request-1');
    expect(command.data.requestId).toBe(command.id);
    expect(command.sent_at).toEqual(expect.any(Number));
    expect({
      ...command,
      id: 'fixture-request-1',
      sent_at: 1704067200000,
      data: { ...command.data, requestId: 'fixture-request-1' },
    }).toEqual(fixture);
  });

  for (const [name, status] of [
    ['success', 200],
    ['failure', 403],
  ] as const) {
    it(`maps the shared shortcut_result ${name} to HTTP`, async () => {
      const fixture = loadTransportFixture(`shortcut_result_${name}`);
      expectKeys(fixture, ['type', 'id', 'from', 'sent_at', 'data']);
      expect(fixture.type).toBe('shortcut_result');
      expect(fixture.id).toBe(fixture.data.requestId);
      expect(fixture.from).toBe('agent');
      expect(fixture.sent_at).toEqual(expect.any(Number));
      expectKeys(fixture.data, [
        'requestId',
        'command',
        'ok',
        'success',
        'message',
        'data',
        ...(name === 'failure' ? ['code', 'error'] : []),
      ]);
      expectKeys(fixture.data.data, [name === 'success' ? 'value' : 'reason']);
      const { response } = await executeFixtureResult(fixture);
      expect(response.status).toBe(status);
      const body = (await response.json()) as any;
      expect(body).toEqual({
        ok: fixture.data.ok,
        success: fixture.data.success,
        request_id: fixture.data.requestId,
        command: fixture.data.command,
        message: fixture.data.message,
        data: { ...fixture.data.data, latency_ms: expect.any(Number) },
        latency_ms: expect.any(Number),
        timestamp: expect.any(Number),
        ...(name === 'failure' ? { code: fixture.data.code, error: fixture.data.error } : {}),
      });
      expect(body.data.latency_ms).toBe(body.latency_ms);
    });
  }

  it('fails a shortcut_result without an explicit ok field', async () => {
    const fixture = loadTransportFixture('shortcut_result_success');
    delete fixture.data.ok;
    const { response } = await executeFixtureResult(fixture);
    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({ ok: false, success: true, message: 'pong' });
  });

  it('accepts the shared shortcut_grant_update and emits the shared ack', async () => {
    const fixture = loadTransportFixture('shortcut_grant_update');
    const ackFixture = loadTransportFixture('shortcut_grant_update_ack');
    expectKeys(fixture, ['type', 'from', 'sent_at', 'data']);
    expect(fixture.type).toBe('shortcut_grant_update');
    expect(fixture.from).toBe('agent');
    expect(fixture.sent_at).toEqual(expect.any(Number));
    expectKeys(fixture.data, ['state', 'grant']);
    expectKeys(fixture.data.grant, [
      'grantId',
      'deviceId',
      'name',
      'tokenHash',
      'tokenPreview',
      'allowedCommands',
      'expiresAt',
      'createdAt',
      'updatedAt',
    ]);
    const storedValues: Record<string, any> = {};
    const registryRef: { current?: SessionManagerDO } = {};
    const env = createEnv(() => registryRef.current);
    const registry = new SessionManagerDO(
      createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME, storedValues),
      env
    );
    registryRef.current = registry;
    const session = new SessionManagerDO(createMockState('fixture-session'), env);
    const agent = createMockSocket();
    await session.addRelaySocket('fixture-session', agent as unknown as WebSocket, {
      deviceId,
      agentIdentityPublicKey: 'fixture-public-key',
    });
    agent.emit('message', { data: JSON.stringify(fixture) });
    await new Promise((resolve) => setTimeout(resolve, 0));
    const ack = agent.send.mock.calls
      .map(([raw]) => JSON.parse(raw as string))
      .find((message) => message.type === 'shortcut_grant_update_ack');
    expect(ack.sent_at).toEqual(expect.any(Number));
    expect({ ...ack, sent_at: 1704067200000 }).toEqual(ackFixture);
    const records = storedValues[SESSION_CONSTANTS.STORAGE_KEYS.DEVICE_REGISTRY];
    expect(records.find((record: any) => record.deviceId === deviceId).shortcutGrants).toEqual([
      fixture.data.grant,
    ]);
  });

  it('does not register removed legacy public routes', async () => {
    const env = createEnv();
    const app = new CicadaRelayApp(env);
    const ctx = {
      waitUntil: jest.fn(),
      passThroughOnException: jest.fn(),
    } as any;

    for (const path of [
      '/send',
      '/api/command',
      '/v1/pairing/code/resolve',
      '/v1/trusted/device/connect',
      '/ws',
      '/api/devices',
      '/api/sessions',
    ]) {
      const response = await app.handle(
        new Request(`http://localhost${path}`, {
          method: path === '/ws' || path.includes('devices') || path.includes('sessions') ? 'GET' : 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: path === '/ws' || path.includes('devices') || path.includes('sessions') ? undefined : '{}',
        }),
        env,
        ctx
      );
      const body = (await response.json()) as any;

      expect(response.status).toBe(404);
      expect(body).toMatchObject({
        ok: false,
        error: 'API endpoint not found',
        path,
      });
    }
  });

  it('accepts agent relay sockets without x-role', async () => {
    const env = createEnv();
    const app = new CicadaRelayApp(env);
    const ctx = { waitUntil: jest.fn(), passThroughOnException: jest.fn() } as any;

    const wsResponse = await app.handle(
      new Request('http://localhost/relay/session-live-1', {
        method: 'GET',
        headers: {
          Upgrade: 'websocket',
          'x-device-id': deviceId,
          'x-agent-identity-public-key': 'agent-public-key',
        },
      }),
      env,
      ctx
    );

    // 与 Workers 一致返回 101；只有 Node 拒绝 101 时 createWebSocketResponse 才退回 200
    expect(wsResponse.status).toBe(101);
  });

  it('executes a valid Shortcuts token through the online agent session', async () => {
    const rooms = new Map<string, SessionManagerDO>();
    const registryRef: { current?: SessionManagerDO } = {};
    const env = createEnv(() => registryRef.current!, rooms);
    const registry = new SessionManagerDO(createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME), env);
    registryRef.current = registry;
    const session = new SessionManagerDO(createMockState('session-live-1'), env);
    rooms.set('session-live-1', session);
    const agent = createMockSocket();

    await session.addRelaySocket('session-live-1', agent as unknown as WebSocket, {
      deviceId,
      agentIdentityPublicKey: 'agent-public-key',
    });

    agent.emit('message', {
      data: JSON.stringify({
        type: 'shortcut_grant_update',
        from: 'agent',
        data: {
          state: 'active',
          grant: {
            grantId: 'grant-1',
            deviceId,
            name: 'iPhone Shortcut',
            tokenHash,
            tokenPreview: 'cicada_sc_te...oken',
            allowedCommands: ['ping', 'status'],
            expiresAt: Date.now() + 60_000,
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        },
      }),
    });
    await new Promise(resolve => setTimeout(resolve, 0));

    const app = new CicadaRelayApp(env);
    const requestPromise = app.handle(
      new Request('http://localhost/v1/shortcuts/command', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          device_id: deviceId,
          command: 'ping',
          request_id: 'req-1',
        }),
      }),
      env,
      { waitUntil: jest.fn(), passThroughOnException: jest.fn() } as any
    );
    await new Promise(resolve => setTimeout(resolve, 0));

    const [sentCommand] = agent.send.mock.calls
      .map(([raw]) => JSON.parse(raw as string))
      .filter(message => message.type === 'shortcut_command');
    const internalRequestId = sentCommand.data.requestId;
    expect(internalRequestId).not.toBe('req-1');
    agent.emit('message', {
      data: JSON.stringify({
        type: 'shortcut_result',
        id: internalRequestId,
        data: {
          requestId: internalRequestId,
          command: 'ping',
          ok: true,
          success: true,
          message: 'pong',
        },
      }),
    });

    const response = await requestPromise;
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({
      ok: true,
      request_id: 'req-1',
      command: 'ping',
      success: true,
      message: 'pong',
    });
  });

  it('keeps concurrent Shortcuts commands independent when clients reuse request_id', async () => {
    const rooms = new Map<string, SessionManagerDO>();
    const registryRef: { current?: SessionManagerDO } = {};
    const env = createEnv(() => registryRef.current!, rooms);
    const registry = new SessionManagerDO(createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME), env);
    registryRef.current = registry;
    const session = new SessionManagerDO(createMockState('session-live-1'), env);
    rooms.set('session-live-1', session);
    const agent = createMockSocket();

    await session.addRelaySocket('session-live-1', agent as unknown as WebSocket, {
      deviceId,
      agentIdentityPublicKey: 'agent-public-key',
    });

    agent.emit('message', {
      data: JSON.stringify({
        type: 'shortcut_grant_update',
        from: 'agent',
        data: {
          state: 'active',
          grant: {
            grantId: 'grant-1',
            deviceId,
            name: 'iPhone Shortcut',
            tokenHash,
            tokenPreview: 'cicada_sc_te...oken',
            allowedCommands: ['ping', 'status'],
            expiresAt: Date.now() + 60_000,
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        },
      }),
    });
    await new Promise(resolve => setTimeout(resolve, 0));

    const app = new CicadaRelayApp(env);
    const postShortcut = (command: string) =>
      app.handle(
        new Request('http://localhost/v1/shortcuts/command', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({
            device_id: deviceId,
            command,
            request_id: 'req-shared',
          }),
        }),
        env,
        { waitUntil: jest.fn(), passThroughOnException: jest.fn() } as any
      );

    const firstRequest = postShortcut('ping');
    const secondRequest = postShortcut('status');
    await new Promise(resolve => setTimeout(resolve, 0));

    const sentCommands = agent.send.mock.calls
      .map(([raw]) => JSON.parse(raw as string))
      .filter(message => message.type === 'shortcut_command');
    expect(sentCommands).toHaveLength(2);
    const firstInternalId = sentCommands[0].data.requestId;
    const secondInternalId = sentCommands[1].data.requestId;
    expect(firstInternalId).not.toBe('req-shared');
    expect(secondInternalId).not.toBe('req-shared');
    expect(firstInternalId).not.toBe(secondInternalId);

    agent.emit('message', {
      data: JSON.stringify({
        type: 'shortcut_result',
        id: secondInternalId,
        data: {
          requestId: secondInternalId,
          command: 'status',
          ok: true,
          success: true,
          message: 'ready',
        },
      }),
    });
    agent.emit('message', {
      data: JSON.stringify({
        type: 'shortcut_result',
        id: firstInternalId,
        data: {
          requestId: firstInternalId,
          command: 'ping',
          ok: true,
          success: true,
          message: 'pong',
        },
      }),
    });

    const firstResponse = await firstRequest;
    const secondResponse = await secondRequest;
    expect(firstResponse.status).toBe(200);
    expect(secondResponse.status).toBe(200);
    expect(await firstResponse.json()).toMatchObject({
      ok: true,
      request_id: 'req-shared',
      command: 'ping',
      message: 'pong',
    });
    expect(await secondResponse.json()).toMatchObject({
      ok: true,
      request_id: 'req-shared',
      command: 'status',
      message: 'ready',
    });
  });

  it('rejects malformed public Shortcuts JSON as an invalid shortcut command', async () => {
    const env = createEnv();
    const app = new CicadaRelayApp(env);
    const response = await app.handle(
      new Request('http://localhost/v1/shortcuts/command', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: '{',
      }),
      env,
      { waitUntil: jest.fn(), passThroughOnException: jest.fn() } as any
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({
      ok: false,
      code: 'invalid_shortcut_command',
    });
  });

  it('rejects malformed internal shortcut dispatch JSON as an invalid shortcut command', async () => {
    const session = new SessionManagerDO(createMockState('session-live-1'), {} as Env);
    const response = await session.fetch(
      new Request('http://session/shortcut/command', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: '{',
      })
    );

    expect(response.status).toBe(400);
    expect(await response.json()).toMatchObject({
      ok: false,
      code: 'invalid_shortcut_command',
    });
  });

  it('returns 504 when the online agent does not answer a shortcut command', async () => {
    const rooms = new Map<string, SessionManagerDO>();
    const registryRef: { current?: SessionManagerDO } = {};
    const env = createEnv(() => registryRef.current!, rooms);
    const registry = new SessionManagerDO(createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME), env);
    registryRef.current = registry;
    const session = new SessionManagerDO(createMockState('session-live-1'), env, {
      shortcutCommandTimeoutMs: 1,
    });
    rooms.set('session-live-1', session);
    const agent = createMockSocket();
    await session.addRelaySocket('session-live-1', agent as unknown as WebSocket, {
      deviceId,
      agentIdentityPublicKey: 'agent-public-key',
    });
    agent.emit('message', {
      data: JSON.stringify({
        type: 'shortcut_grant_update',
        from: 'agent',
        data: {
          state: 'active',
          grant: {
            grantId: 'grant-1',
            deviceId,
            name: 'iPhone Shortcut',
            tokenHash,
            tokenPreview: 'cicada_sc_te...oken',
            allowedCommands: ['ping'],
            expiresAt: Date.now() + 60_000,
            createdAt: Date.now(),
            updatedAt: Date.now(),
          },
        },
      }),
    });
    await new Promise(resolve => setTimeout(resolve, 0));

    const app = new CicadaRelayApp(env);
    const response = await app.handle(
      new Request('http://localhost/v1/shortcuts/command', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({ device_id: deviceId, command: 'ping', request_id: 'req-timeout' }),
      }),
      env,
      { waitUntil: jest.fn(), passThroughOnException: jest.fn() } as any
    );

    expect(agent.send).toHaveBeenCalledWith(expect.stringContaining('"type":"shortcut_command"'));
    expect(response.status).toBe(504);
    expect((await response.json()) as any).toMatchObject({
      ok: false,
      error: 'Internal server error',
      request_id: expect.any(String),
    });
  });

  it('rejects invalid, expired, revoked, unauthorized, and offline shortcut commands', async () => {
    const now = Date.now();
    const registryRef: { current?: SessionManagerDO } = {};
    const env = createEnv(() => registryRef.current!);
    const registry = new SessionManagerDO(
      createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME, {
        [SESSION_CONSTANTS.STORAGE_KEYS.DEVICE_REGISTRY]: [
          {
            deviceId,
            connected: false,
            liveSessionId: 'session-live-1',
            lastSeen: now,
            shortcutGrants: [
              {
                grantId: 'grant-1',
                deviceId,
                name: 'active',
                tokenHash,
                tokenPreview: 'preview',
                allowedCommands: ['ping'],
                expiresAt: now + 60_000,
                createdAt: now,
                updatedAt: now,
              },
              {
                grantId: 'grant-expired',
                deviceId,
                name: 'expired',
                tokenHash: Buffer.from('expired-hash').toString('base64url'),
                tokenPreview: 'preview',
                allowedCommands: ['ping'],
                expiresAt: now - 1,
                createdAt: now,
                updatedAt: now,
              },
              {
                grantId: 'grant-revoked',
                deviceId,
                name: 'revoked',
                tokenHash: Buffer.from('revoked-hash').toString('base64url'),
                tokenPreview: 'preview',
                allowedCommands: ['ping'],
                expiresAt: now + 60_000,
                revokedAt: now,
                createdAt: now,
                updatedAt: now,
              },
            ],
          },
        ],
      }),
      env,
      { agentAbsenceGraceMs: 1 }
    );
    registryRef.current = registry;
    const app = new CicadaRelayApp(env);
    const ctx = { waitUntil: jest.fn(), passThroughOnException: jest.fn() } as any;

    const post = async (hashBytes: string, command = 'ping') => {
      (global.crypto.subtle.digest as jest.Mock).mockResolvedValueOnce(digestBytes(hashBytes));
      return app.handle(
        new Request('http://localhost/v1/shortcuts/command', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ device_id: deviceId, command, request_id: hashBytes }),
        }),
        env,
        ctx
      );
    };

    expect(((await (await post('unknown')).json()) as any).code).toBe('invalid_token');
    expect(((await (await post('expired-hash')).json()) as any).code).toBe('grant_expired');
    expect(((await (await post('revoked-hash')).json()) as any).code).toBe('grant_revoked');
    expect(((await (await post('token-hash', 'lock')).json()) as any).code).toBe('command_not_allowed');
    const offline = await post('token-hash');
    expect(offline.status).toBe(503);
    expect((await offline.json()) as any).toMatchObject({
      ok: false,
      error: 'Internal server error',
      request_id: expect.any(String),
    });
  });
});
