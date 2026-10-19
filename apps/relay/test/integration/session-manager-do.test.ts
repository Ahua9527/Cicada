/**
 * SessionManagerDO 真实入口测试：只走 fetch()、agent WebSocket 消息和 worker 入口。
 */

import {
  createHash,
  createPublicKey,
  generateKeyPairSync,
  randomUUID,
  sign as signBytes,
  verify as verifyBytes,
  type KeyObject,
} from 'node:crypto';
import { readFileSync } from 'node:fs';
import { SessionManagerDO } from '../../src/infrastructure/persistence';
import { SESSION_CONSTANTS } from '../../src/config/constants';
import { CicadaRelayApp } from '../../src/presentation/app';
import type { Env } from '../../src/types';

// Ed25519 公钥 raw 字节前面加上固定的 SPKI DER 头，才能交给 node:crypto 校验。
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');
const deviceId = 'MAC_1234567890ABCDEF1234567890ABCDEF';
const otherDeviceId = 'MAC_FEDCBA0987654321FEDCBA0987654321';
const registryKey = SESSION_CONSTANTS.STORAGE_KEYS.DEVICE_REGISTRY;
const enrollmentCodesKey = SESSION_CONSTANTS.STORAGE_KEYS.ENROLLMENT_CODES;

type Identity = { publicKey: string; privateKey: KeyObject };

const createIdentity = (): Identity => {
  const pair = generateKeyPairSync('ed25519');
  return {
    privateKey: pair.privateKey,
    publicKey: pair.publicKey
      .export({ format: 'der', type: 'spki' })
      .subarray(ED25519_SPKI_PREFIX.byteLength)
      .toString('base64'),
  };
};

const createMockState = (
  name?: string,
  storedValues: Record<string, any> = {}
): DurableObjectState =>
  ({
    id: {
      toString: () => name ?? 'anonymous-id',
      equals: jest.fn(),
      name,
    },
    storage: {
      get: jest.fn((key: string) => Promise.resolve(storedValues[key] ?? null)),
      put: jest.fn((key: string | Record<string, unknown>, value?: unknown) => {
        if (typeof key === 'string') {
          storedValues[key] = value;
        } else {
          Object.assign(storedValues, key);
        }
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
  return {
    accept: jest.fn(),
    send: jest.fn(),
    close: jest.fn(),
    addEventListener: jest.fn((type: string, listener: (event: any) => void) => {
      listeners.set(type, [...(listeners.get(type) ?? []), listener]);
    }),
    emit(type: string, event: any = {}) {
      for (const listener of listeners.get(type) ?? []) {
        listener(event);
      }
    },
    sent(): any[] {
      return this.send.mock.calls.map(([raw]: [string]) => JSON.parse(raw));
    },
  };
};

const tick = (ms = 0) => new Promise(resolve => setTimeout(resolve, ms));

const post = (target: SessionManagerDO, path: string, body: unknown, headers = {}) =>
  target.fetch(
    new Request(`http://session${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...headers },
      body: typeof body === 'string' ? body : JSON.stringify(body),
    })
  );

const createRegistry = (storedValues: Record<string, any> = {}, env = {} as Env) =>
  new SessionManagerDO(createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME, storedValues), env);

/** 让会话房间把注册表和其他房间解析到给定实例。 */
const createNamespaceEnv = (resolve: (name: string) => SessionManagerDO | { fetch: () => never }) =>
  ({
    CICADA_SESSIONS: {
      idFromName: jest.fn((name: string) => ({ name })),
      get: jest.fn((id: { name: string }) => resolve(id.name)),
    },
  }) as unknown as Env;

const transcript = (fields: string[]) =>
  Buffer.concat(
    fields.flatMap(field => {
      const data = Buffer.from(field, 'utf8');
      const length = Buffer.alloc(4);
      length.writeUInt32BE(data.byteLength);
      return [length, data];
    })
  );

const activeGrant = (overrides: Record<string, unknown> = {}) => ({
  grantId: 'grant-1',
  deviceId,
  name: 'iPhone Shortcut',
  tokenHash: 'token-hash',
  tokenPreview: 'cicada_sc_te...oken',
  allowedCommands: ['ping'],
  expiresAt: Date.now() + 60_000,
  createdAt: Date.now(),
  updatedAt: Date.now(),
  ...overrides,
});

describe('SessionManagerDO real entry points', () => {
  const identity = createIdentity();
  const publicKey = identity.publicKey;

  beforeEach(() => {
    // setup.ts 把 crypto.subtle 换成了空 mock；这里接到 node:crypto，签名校验和哈希都走真实算法。
    jest.spyOn(crypto.subtle, 'importKey').mockImplementation((async (
      _format: string,
      keyData: ArrayBuffer
    ) =>
      createPublicKey({
        key: Buffer.concat([ED25519_SPKI_PREFIX, Buffer.from(keyData)]),
        format: 'der',
        type: 'spki',
      })) as any);
    jest
      .spyOn(crypto.subtle, 'verify')
      .mockImplementation((async (
        _algorithm: unknown,
        key: any,
        signature: ArrayBuffer,
        data: ArrayBuffer
      ) => verifyBytes(null, Buffer.from(data), key, Buffer.from(signature))) as any);
    jest.spyOn(crypto.subtle, 'digest').mockImplementation((async (
      _algorithm: string,
      data: Uint8Array
    ) => {
      const digest = createHash('sha256').update(data).digest();
      return digest.buffer.slice(digest.byteOffset, digest.byteOffset + digest.byteLength);
    }) as any);
  });

  const signRegistration = (
    fields: {
      deviceId: string;
      sessionId: string;
      timestamp: number;
      nonce: string;
      enrollmentCode?: string;
    },
    signer: Identity = identity
  ) =>
    signBytes(
      null,
      transcript([
        fields.enrollmentCode ? 'cicada-agent-registration-v2' : 'cicada-agent-registration-v1',
        fields.deviceId,
        fields.sessionId,
        signer.publicKey,
        String(fields.timestamp),
        fields.nonce,
        ...(fields.enrollmentCode ? [fields.enrollmentCode] : []),
      ]),
      signer.privateKey
    ).toString('base64');

  const registerOnline = (registry: SessionManagerDO, body: Record<string, unknown>) =>
    post(registry, '/registry/agent-online', {
      deviceId,
      sessionId: 'session-1',
      agentIdentityPublicKey: publicKey,
      ...body,
    });

  const signedRegistration = async (sessionId: string, nonce: string, timestamp = Date.now()) => ({
    sessionId,
    registrationTimestamp: timestamp,
    registrationNonce: nonce,
    registrationSignature: signRegistration({ deviceId, sessionId, timestamp, nonce }),
  });

  const issueEnrollmentCode = async (registry: SessionManagerDO) => {
    const response = await post(registry, '/registry/admin-enrollment-code', {});
    return ((await response.json()) as { enrollmentCode: string }).enrollmentCode;
  };

  /** 带注册码的首次登记（v2 签名）；换 signer 或 signedDeviceId 可以造出别的设备的签名。 */
  const enrollmentRegistration = (
    enrollmentCode: string,
    {
      sessionId = 'session-1',
      nonce = randomUUID(),
      signer = identity,
      signedDeviceId = deviceId,
    }: { sessionId?: string; nonce?: string; signer?: Identity; signedDeviceId?: string } = {}
  ) => {
    const timestamp = Date.now();
    return {
      sessionId,
      agentIdentityPublicKey: signer.publicKey,
      enrollmentCode,
      registrationTimestamp: timestamp,
      registrationNonce: nonce,
      registrationSignature: signRegistration(
        { deviceId: signedDeviceId, sessionId, timestamp, nonce, enrollmentCode },
        signer
      ),
    };
  };

  /** 签发注册码并完成首次登记，得到一台已绑定且在线的设备。 */
  const enroll = async (registry: SessionManagerDO, sessionId = 'session-1') => {
    const code = await issueEnrollmentCode(registry);
    const response = await registerOnline(registry, enrollmentRegistration(code, { sessionId }));
    expect(response.status).toBe(200);
  };

  describe('routing', () => {
    it('answers OPTIONS and unknown paths', async () => {
      const room = new SessionManagerDO(createMockState('room'), {} as Env);

      const options = await room.fetch(
        new Request('http://session/anything', { method: 'OPTIONS' })
      );
      expect(options.status).toBe(204);

      const unknown = await room.fetch(new Request('http://session/registry/unknown'));
      expect(unknown.status).toBe(404);
      expect(await unknown.json()).toEqual({
        success: false,
        error: 'Not found',
        path: '/registry/unknown',
      });
    });

    it.each([
      ['/shortcut/command', 'GET', 'POST'],
      ['/registry/agent-online', 'GET', 'POST'],
      ['/registry/agent-offline', 'GET', 'POST'],
      ['/registry/shortcut-grant-update', 'GET', 'POST'],
      ['/registry/admin-reset-device', 'GET', 'POST'],
      ['/registry/admin-enrollment-code', 'GET', 'POST'],
      ['/v1/shortcuts/command', 'GET', 'POST'],
      ['/registry/devices', 'POST', 'GET'],
    ])('rejects %s with %s', async (path, method, allowed) => {
      const response = await createRegistry().fetch(
        new Request(`http://session${path}`, { method })
      );

      expect(response.status).toBe(405);
      expect(response.headers.get('Allow')).toBe(allowed);
    });
  });

  describe('registry agent-online', () => {
    it('binds the identity key with an enrollment code and consumes the code', async () => {
      const storedValues: Record<string, any> = {};
      const registry = createRegistry(storedValues);
      const code = await issueEnrollmentCode(registry);

      const response = await registerOnline(registry, enrollmentRegistration(code));

      expect(response.status).toBe(200);
      expect(await response.json()).toMatchObject({
        ok: true,
        device: {
          deviceId,
          connected: true,
          liveSessionId: 'session-1',
          agentIdentityPublicKey: publicKey,
        },
      });
      expect(storedValues[registryKey]).toEqual([
        expect.objectContaining({ deviceId, connected: true, agentIdentityPublicKey: publicKey }),
      ]);
      expect(storedValues[enrollmentCodesKey]).toEqual([
        expect.objectContaining({ usedAt: Date.now() }),
      ]);

      // 码已作废：另一台未绑定的设备拿同一个码登记会被拒。
      const reused = await registerOnline(registry, {
        ...enrollmentRegistration(code, { signedDeviceId: otherDeviceId }),
        deviceId: otherDeviceId,
      });
      expect(reused.status).toBe(409);
      expect(await reused.json()).toMatchObject({ code: 'agent_enrollment_code_used' });
    });

    it('requires an enrollment code and a signature before binding an unbound device', async () => {
      const storedValues: Record<string, any> = {};
      const registry = createRegistry(storedValues);

      const unsigned = await registerOnline(registry, {});
      expect(unsigned.status).toBe(401);
      expect(await unsigned.json()).toMatchObject({ code: 'agent_enrollment_code_required' });

      // 只有 v1 签名、没有注册码，同样不能首次登记。
      const signedV1 = await registerOnline(
        registry,
        await signedRegistration('session-1', 'nonce-v1')
      );
      expect(signedV1.status).toBe(401);
      expect(await signedV1.json()).toMatchObject({ code: 'agent_enrollment_code_required' });

      const codeOnly = await registerOnline(registry, {
        enrollmentCode: await issueEnrollmentCode(registry),
      });
      expect(codeOnly.status).toBe(401);
      expect(await codeOnly.json()).toMatchObject({
        code: 'agent_registration_signature_required',
      });
      expect(storedValues[registryKey]).toBeUndefined();
    });

    it('rejects unknown and expired enrollment codes', async () => {
      const registry = createRegistry();

      const unknown = await registerOnline(
        registry,
        enrollmentRegistration('cicada_enroll_never-issued')
      );
      expect(unknown.status).toBe(403);
      expect(await unknown.json()).toMatchObject({ code: 'agent_enrollment_code_invalid' });

      const code = await issueEnrollmentCode(registry);
      (Date.now as unknown as jest.Mock).mockReturnValue(
        Date.now() + SESSION_CONSTANTS.ENROLLMENT_CODE_TTL_MS
      );
      const expired = await registerOnline(registry, enrollmentRegistration(code));
      expect(expired.status).toBe(401);
      expect(await expired.json()).toMatchObject({ code: 'agent_enrollment_code_expired' });
    });

    it('rejects enrollment signed by another key or for another device and keeps the code', async () => {
      const registry = createRegistry();
      const code = await issueEnrollmentCode(registry);

      for (const forged of [
        // 声明的是本机公钥，签名却出自另一把私钥。
        {
          ...enrollmentRegistration(code, { signer: createIdentity() }),
          agentIdentityPublicKey: publicKey,
        },
        // 签名内容里写的是另一台设备。
        enrollmentRegistration(code, { signedDeviceId: otherDeviceId }),
      ]) {
        const response = await registerOnline(registry, forged);
        expect(response.status).toBe(403);
        expect(await response.json()).toMatchObject({
          code: 'invalid_agent_registration_signature',
        });
      }

      const accepted = await registerOnline(registry, enrollmentRegistration(code));
      expect(accepted.status).toBe(200);
    });

    it('accepts a retry with the used code once the device is bound to the same key', async () => {
      const storedValues: Record<string, any> = {};
      const registry = createRegistry(storedValues);
      const code = await issueEnrollmentCode(registry);
      await registerOnline(registry, enrollmentRegistration(code));

      // Mac 没收到上次登记成功的响应：同一把钥匙带同一个码重连，不再核销注册码。
      const retry = await registerOnline(
        registry,
        enrollmentRegistration(code, { sessionId: 'session-2' })
      );

      expect(retry.status).toBe(200);
      expect(storedValues[registryKey][0]).toMatchObject({ liveSessionId: 'session-2' });
    });

    it('logs rejected enrollment codes without the code or the device id', async () => {
      const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
      const guessedCode = 'cicada_enroll_guessed-code';

      const response = await post(
        createRegistry(),
        '/registry/agent-online',
        { deviceId, ...enrollmentRegistration(guessedCode) },
        { 'X-Request-ID': 'req-enroll' }
      );

      expect(response.status).toBe(403);
      expect(warn).toHaveBeenCalledTimes(1);
      const eventText = String(warn.mock.calls[0]?.[0]);
      expect(JSON.parse(eventText)).toEqual({
        level: 'warn',
        message: 'Agent enrollment rejected',
        request_id: 'req-enroll',
        security_event: 'agent_enrollment_rejected',
        reason: 'agent_enrollment_code_invalid',
        status: 403,
        do_operation: 'registry_agent_online',
      });
      expect(eventText).not.toContain(guessedCode);
      expect(eventText).not.toContain(deviceId);
    });

    it('rejects a different identity key after the first-seen binding', async () => {
      const registry = createRegistry();
      await enroll(registry);

      const response = await registerOnline(registry, { agentIdentityPublicKey: 'other-key' });

      expect(response.status).toBe(403);
      expect(await response.json()).toMatchObject({ ok: false, code: 'agent_identity_mismatch' });
    });

    it('requires a signature once the device is bound', async () => {
      const registry = createRegistry();
      await enroll(registry);

      const response = await registerOnline(registry, { sessionId: 'session-2' });

      expect(response.status).toBe(401);
      expect(await response.json()).toMatchObject({
        code: 'agent_registration_signature_required',
      });
    });

    it('rejects registration timestamps outside the allowed skew', async () => {
      const registry = createRegistry();
      await enroll(registry);

      const response = await registerOnline(
        registry,
        await signedRegistration(
          'session-2',
          'nonce-old',
          Date.now() - SESSION_CONSTANTS.AGENT_REGISTRATION_SKEW - 1
        )
      );

      expect(response.status).toBe(401);
      expect(await response.json()).toMatchObject({ code: 'agent_registration_expired' });
    });

    it('rejects a signature over a different transcript', async () => {
      const registry = createRegistry();
      await enroll(registry);
      const signed = await signedRegistration('session-signed', 'nonce-1');

      const response = await registerOnline(registry, { ...signed, sessionId: 'session-other' });

      expect(response.status).toBe(403);
      expect(await response.json()).toMatchObject({ code: 'invalid_agent_registration_signature' });
    });

    it('accepts a valid signature once and rejects the replayed nonce', async () => {
      const storedValues: Record<string, any> = {};
      const registry = createRegistry(storedValues);
      await enroll(registry);
      const signed = await signedRegistration('session-2', 'nonce-1');

      const accepted = await registerOnline(registry, signed);
      expect(accepted.status).toBe(200);
      expect(storedValues[registryKey][0]).toMatchObject({ liveSessionId: 'session-2' });

      const replayed = await registerOnline(registry, signed);
      expect(replayed.status).toBe(409);
      expect(await replayed.json()).toMatchObject({ code: 'agent_registration_replayed' });

      const fresh = await registerOnline(
        registry,
        await signedRegistration('session-3', 'nonce-2')
      );
      expect(fresh.status).toBe(200);
      expect(storedValues[registryKey][0]).toMatchObject({ liveSessionId: 'session-3' });
    });
  });

  describe('registry admin-enrollment-code', () => {
    it('returns the code once, stores only its hash and drops stale codes', async () => {
      const stale = {
        codeHash: 'stale-hash',
        createdAt: 0,
        expiresAt: Date.now() - SESSION_CONSTANTS.ENROLLMENT_CODE_RETENTION_MS - 1,
      };
      const storedValues: Record<string, any> = { [enrollmentCodesKey]: [stale] };
      const registry = createRegistry(storedValues);
      await tick();

      const response = await post(registry, '/registry/admin-enrollment-code', {});

      expect(response.status).toBe(201);
      const body = (await response.json()) as { enrollmentCode: string; expiresAt: number };
      expect(body).toEqual({
        ok: true,
        enrollmentCode: expect.stringMatching(/^cicada_enroll_[\w-]{22}$/),
        expiresAt: Date.now() + SESSION_CONSTANTS.ENROLLMENT_CODE_TTL_MS,
      });
      expect(storedValues[enrollmentCodesKey]).toEqual([
        {
          codeHash: createHash('sha256').update(body.enrollmentCode).digest('base64url'),
          createdAt: Date.now(),
          expiresAt: body.expiresAt,
        },
      ]);
      expect(JSON.stringify(storedValues)).not.toContain(body.enrollmentCode);
    });
  });

  describe('registry agent-offline', () => {
    it('validates the body and only marks the matching live session offline', async () => {
      const storedValues: Record<string, any> = {};
      const registry = createRegistry(storedValues);
      await enroll(registry);

      const missing = await post(registry, '/registry/agent-offline', {});
      expect(missing.status).toBe(400);

      await post(registry, '/registry/agent-offline', { deviceId, sessionId: 'session-old' });
      expect(storedValues[registryKey][0]).toMatchObject({ connected: true });

      const offline = await post(registry, '/registry/agent-offline', {
        deviceId,
        sessionId: 'session-1',
      });
      expect(await offline.json()).toEqual({ ok: true, success: true });
      expect(storedValues[registryKey][0]).toMatchObject({ connected: false });
    });
  });

  describe('registry shortcut-grant-update', () => {
    const update = (registry: SessionManagerDO, body: Record<string, unknown>) =>
      post(registry, '/registry/shortcut-grant-update', {
        deviceId,
        sessionId: 'session-1',
        state: 'active',
        grant: activeGrant(),
        ...body,
      });

    it('rejects missing fields, offline targets and invalid grants', async () => {
      const registry = createRegistry();

      const missing = await update(registry, { grant: {} });
      expect(missing.status).toBe(400);
      expect(await missing.json()).toMatchObject({ code: 'invalid_shortcut_grant_update' });

      const offline = await update(registry, {});
      expect(offline.status).toBe(404);
      expect(await offline.json()).toMatchObject({ code: 'device_unavailable' });

      await enroll(registry);
      const staleSession = await update(registry, { sessionId: 'session-old' });
      expect(staleSession.status).toBe(404);

      const expired = await update(registry, { grant: activeGrant({ expiresAt: Date.now() }) });
      expect(expired.status).toBe(400);
      expect(await expired.json()).toMatchObject({ code: 'invalid_shortcut_grant_update' });
    });

    it('replaces grants by id and records revocation', async () => {
      const storedValues: Record<string, any> = {};
      const registry = createRegistry(storedValues);
      await enroll(registry);

      expect(await (await update(registry, {})).json()).toEqual({
        ok: true,
        success: true,
        grantId: 'grant-1',
        state: 'active',
      });
      await update(registry, { grant: activeGrant({ name: 'Renamed' }) });
      expect(storedValues[registryKey][0].shortcutGrants).toEqual([
        expect.objectContaining({ grantId: 'grant-1', name: 'Renamed' }),
      ]);

      const revoked = await update(registry, { state: 'revoked', grant: { grantId: 'grant-1' } });
      expect(await revoked.json()).toMatchObject({
        ok: true,
        grantId: 'grant-1',
        state: 'revoked',
      });
      expect(storedValues[registryKey][0].shortcutGrants).toEqual([
        expect.objectContaining({ grantId: 'grant-1', revokedAt: Date.now() }),
      ]);
    });
  });

  describe('registry admin-reset-device', () => {
    it('validates the body and removes the first-seen binding', async () => {
      const storedValues: Record<string, any> = {};
      const registry = createRegistry(storedValues);
      await enroll(registry);

      const invalidJson = await post(registry, '/registry/admin-reset-device', '{');
      expect(invalidJson.status).toBe(400);
      expect(await invalidJson.json()).toMatchObject({ code: 'invalid_body' });

      const invalidId = await post(registry, '/registry/admin-reset-device', { deviceId: 'bad' });
      expect(invalidId.status).toBe(400);
      expect(await invalidId.json()).toMatchObject({ code: 'invalid_device_id' });

      const reset = await post(registry, '/registry/admin-reset-device', { deviceId });
      expect(await reset.json()).toEqual({ ok: true, deviceId, existed: true });
      expect(storedValues[registryKey]).toEqual([]);

      // 解绑后可以换一把新密钥、用新注册码重新登记。
      const rebound = await registerOnline(
        registry,
        enrollmentRegistration(await issueEnrollmentCode(registry), { signer: createIdentity() })
      );
      expect(rebound.status).toBe(200);
    });

    it('reports a missing device without writing storage', async () => {
      const state = createMockState(SESSION_CONSTANTS.REGISTRY_DO_NAME);
      const registry = new SessionManagerDO(state, {} as Env);

      const response = await post(registry, '/registry/admin-reset-device', {
        deviceId: otherDeviceId,
      });

      expect(await response.json()).toEqual({ ok: true, deviceId: otherDeviceId, existed: false });
      expect(state.storage.put).not.toHaveBeenCalled();
    });
  });

  describe('registry Shortcuts command', () => {
    const token = 'cicada_sc_real_token';
    const tokenHash = createHash('sha256').update(token).digest('base64url');
    const command = (
      registry: SessionManagerDO,
      body: unknown,
      authorization = `Bearer ${token}`
    ) => post(registry, '/v1/shortcuts/command', body, { Authorization: authorization });

    const registryWithGrant = (env = {} as Env, record: Record<string, unknown> = {}) =>
      createRegistry(
        {
          [registryKey]: [
            {
              deviceId,
              connected: true,
              liveSessionId: 'session-1',
              lastSeen: Date.now(),
              shortcutGrants: [activeGrant({ tokenHash, allowedCommands: ['ping', 'status'] })],
              ...record,
            },
          ],
        },
        env
      );

    it('rejects missing tokens and malformed bodies', async () => {
      const registry = registryWithGrant();

      const noToken = await command(
        registry,
        { device_id: deviceId, command: 'ping' },
        'Bearer nope'
      );
      expect(noToken.status).toBe(401);
      expect(await noToken.json()).toMatchObject({ code: 'invalid_token' });

      const invalidJson = await command(registry, '[]');
      expect(invalidJson.status).toBe(400);
      expect(await invalidJson.json()).toMatchObject({ code: 'invalid_shortcut_command' });

      const missingDevice = await command(registry, { command: 'ping', request_id: 'req-1' });
      expect(missingDevice.status).toBe(400);
      expect(await missingDevice.json()).toMatchObject({
        code: 'invalid_shortcut_command',
        request_id: 'req-1',
        command: 'ping',
      });
    });

    it('fails closed when agent routing is unavailable', async () => {
      await tick();
      const response = await command(registryWithGrant(), { device_id: deviceId, command: 'ping' });

      expect(response.status).toBe(503);
    });

    it('routes an authorized command with its params to the live agent room', async () => {
      const agent = createMockSocket();
      const env = createNamespaceEnv(() => room);
      const room = new SessionManagerDO(createMockState('session-1'), env);
      await room.addRelaySocket('session-1', agent as unknown as WebSocket);
      const registry = registryWithGrant(env);
      await tick();

      const pending = command(registry, {
        device_id: deviceId,
        command: 'status',
        request_id: 'req-status',
        params: { verbose: true },
      });
      await tick();
      const [dispatched] = agent.sent();
      expect(dispatched).toMatchObject({
        type: 'shortcut_command',
        data: { grantId: 'grant-1', command: 'status', params: { verbose: true } },
      });
      agent.emit('message', {
        data: JSON.stringify({
          type: 'shortcut_result',
          id: dispatched.id,
          data: {
            requestId: dispatched.id,
            ok: true,
            success: true,
            resultData: { uptime: 42 },
          },
        }),
      });

      const response = await pending;
      expect(response.status).toBe(200);
      expect(await response.json()).toMatchObject({
        ok: true,
        request_id: 'req-status',
        command: 'status',
        data: { uptime: 42, latency_ms: expect.any(Number) },
      });
    });
  });

  describe('room Shortcuts dispatch', () => {
    const dispatch = (room: SessionManagerDO, body: Record<string, unknown> = {}) =>
      post(room, '/shortcut/command', {
        requestId: 'req-1',
        deviceId,
        grantId: 'grant-1',
        command: 'ping',
        ...body,
      });

    const roomWithAgent = async (options = {}) => {
      const agent = createMockSocket();
      const room = new SessionManagerDO(createMockState('session-1'), {} as Env, options);
      await room.addRelaySocket('session-1', agent as unknown as WebSocket, {
        deviceId,
        agentIdentityPublicKey: publicKey,
      });
      return { room, agent };
    };

    it('rejects incomplete dispatches, other devices and offline agents', async () => {
      const { room } = await roomWithAgent();

      const missing = await dispatch(room, { grantId: '' });
      expect(missing.status).toBe(400);
      expect(await missing.json()).toMatchObject({
        code: 'invalid_shortcut_command',
        request_id: 'req-1',
      });

      expect((await dispatch(room, { deviceId: otherDeviceId })).status).toBe(503);

      const empty = new SessionManagerDO(createMockState('session-2'), {} as Env);
      expect((await dispatch(empty)).status).toBe(503);
    });

    it('maps agent failures to their HTTP status and ignores unknown results', async () => {
      const { room, agent } = await roomWithAgent();

      const pending = dispatch(room);
      await tick();
      const [dispatched] = agent.sent();
      agent.emit('message', { data: JSON.stringify({ type: 'shortcut_result', data: {} }) });
      agent.emit('message', {
        data: JSON.stringify({ type: 'shortcut_result', id: 'shortcut-unknown', data: {} }),
      });
      agent.emit('message', {
        data: JSON.stringify({
          type: 'shortcut_result',
          id: dispatched.id,
          data: {
            ok: false,
            success: false,
            code: 'command_not_allowed',
            error: 'Not allowed on this Mac.',
          },
        }),
      });

      const response = await pending;
      expect(response.status).toBe(403);
      expect(await response.json()).toMatchObject({
        ok: false,
        request_id: 'req-1',
        command: 'ping',
        code: 'command_not_allowed',
        error: 'Not allowed on this Mac.',
      });
    });

    it('fails pending commands when the agent disconnects', async () => {
      const { room, agent } = await roomWithAgent({ agentAbsenceGraceMs: 60_000 });

      const pending = dispatch(room);
      await tick();
      agent.emit('close');

      expect((await pending).status).toBe(503);
    });

    it('times out when the agent never answers', async () => {
      const { room } = await roomWithAgent({ shortcutCommandTimeoutMs: 1 });

      expect((await dispatch(room)).status).toBe(504);
    });
  });

  describe('agent relay socket', () => {
    const upgrade = (room: SessionManagerDO, headers: Record<string, string>) =>
      room.fetch(
        new Request('http://session/relay/session-2', {
          headers: {
            Upgrade: 'websocket',
            'X-Session-ID': 'session-2',
            'X-Device-ID': deviceId,
            'X-Agent-Identity-Public-Key': publicKey,
            ...headers,
          },
        })
      );
    const lastServerSocket = () =>
      ((globalThis as any).WebSocketPair as jest.Mock).mock.results.at(-1)?.value[1];

    it('forwards signed registration headers to the registry', async () => {
      const storedValues: Record<string, any> = {};
      const registry = createRegistry(storedValues);
      await enroll(registry);
      const room = new SessionManagerDO(
        createMockState('session-2'),
        createNamespaceEnv(() => registry)
      );
      const signed = await signedRegistration('session-2', 'nonce-ws');

      const response = await upgrade(room, {
        'X-Agent-Registration-Timestamp': String(signed.registrationTimestamp),
        'X-Agent-Registration-Nonce': signed.registrationNonce,
        'X-Agent-Registration-Signature': signed.registrationSignature,
      });

      expect(response.status).toBe(101);
      expect(storedValues[registryKey][0]).toMatchObject({
        connected: true,
        liveSessionId: 'session-2',
      });
    });

    it('closes the socket when the registry rejects the agent', async () => {
      const registry = createRegistry();
      await enroll(registry);
      const room = new SessionManagerDO(
        createMockState('session-2'),
        createNamespaceEnv(() => registry)
      );

      const response = await upgrade(room, { 'X-Agent-Identity-Public-Key': 'other-key' });

      expect(response.status).toBe(429);
      expect(await response.json()).toEqual({
        success: false,
        error: 'Agent identity key does not match first-seen binding.',
        code: 'agent_identity_mismatch',
      });
      expect(lastServerSocket().close).toHaveBeenCalledWith(
        1013,
        'Agent identity key does not match first-seen binding.'
      );
    });

    it('rejects the agent when the registry cannot be reached', async () => {
      const room = new SessionManagerDO(
        createMockState('session-2'),
        createNamespaceEnv(() => ({
          fetch: () => {
            throw new Error('registry down');
          },
        }))
      );

      const response = await upgrade(room, {});

      expect(response.status).toBe(429);
      expect(await response.json()).toMatchObject({ error: 'registry down' });
    });

    it('keeps the registry online when the agent reconnects within the grace period', async () => {
      const storedValues: Record<string, any> = {};
      const registry = createRegistry(storedValues);
      const room = new SessionManagerDO(
        createMockState('session-1'),
        createNamespaceEnv(() => registry),
        { agentAbsenceGraceMs: 5 }
      );
      const first = createMockSocket();
      await room.addRelaySocket('session-1', first as unknown as WebSocket, {
        deviceId,
        ...enrollmentRegistration(await issueEnrollmentCode(registry)),
      });

      first.emit('close');
      await room.addRelaySocket('session-1', createMockSocket() as unknown as WebSocket);
      await tick(15);

      expect(storedValues[registryKey][0]).toMatchObject({ connected: true });
    });

    it('enrolls a new Mac with a code issued through the worker admin API', async () => {
      const adminToken = 'test-admin-token';
      const storedValues: Record<string, any> = {};
      const registry = createRegistry(storedValues);
      const rooms = new Map<string, SessionManagerDO>();
      const env: Env = {
        ...createNamespaceEnv(name => {
          if (name === SESSION_CONSTANTS.REGISTRY_DO_NAME) {
            return registry;
          }
          if (!rooms.has(name)) {
            rooms.set(name, new SessionManagerDO(createMockState(name), env));
          }
          return rooms.get(name)!;
        }),
        RATE_LIMIT_ENABLED: 'false',
        CICADA_ADMIN_TOKEN: adminToken,
      };
      const app = new CicadaRelayApp(env);
      const ctx = { waitUntil: jest.fn(), passThroughOnException: jest.fn() } as any;
      const upgradeThroughWorker = (
        agentDeviceId: string,
        enrollment: ReturnType<typeof enrollmentRegistration>
      ) =>
        app.handle(
          new Request(`http://localhost/relay/${enrollment.sessionId}`, {
            headers: {
              Upgrade: 'websocket',
              'x-device-id': agentDeviceId,
              'x-agent-identity-public-key': enrollment.agentIdentityPublicKey,
              'x-agent-enrollment-code': enrollment.enrollmentCode,
              'x-agent-registration-timestamp': String(enrollment.registrationTimestamp),
              'x-agent-registration-nonce': enrollment.registrationNonce,
              'x-agent-registration-signature': enrollment.registrationSignature,
            },
          }),
          env,
          ctx
        );

      const issued = await app.handle(
        new Request('http://localhost/v1/admin/enrollment-codes', {
          method: 'POST',
          headers: { Authorization: `Bearer ${adminToken}` },
        }),
        env,
        ctx
      );
      expect(issued.status).toBe(201);
      expect(issued.headers.get('Cache-Control')).toBe('no-store');
      const { enrollmentCode } = (await issued.json()) as { enrollmentCode: string };

      const enrolled = await upgradeThroughWorker(
        deviceId,
        enrollmentRegistration(enrollmentCode, { sessionId: 'live-enroll-1' })
      );
      expect(enrolled.status).toBe(101);
      expect(storedValues[registryKey]).toEqual([
        expect.objectContaining({
          deviceId,
          connected: true,
          liveSessionId: 'live-enroll-1',
          agentIdentityPublicKey: publicKey,
        }),
      ]);

      // 同一个码不能再给别的设备用；失败的升级响应里带着具体错误码。
      const reused = await upgradeThroughWorker(
        otherDeviceId,
        enrollmentRegistration(enrollmentCode, {
          sessionId: 'live-enroll-2',
          signedDeviceId: otherDeviceId,
        })
      );
      expect(reused.status).toBe(429);
      expect(await reused.json()).toMatchObject({ code: 'agent_enrollment_code_used' });
    });

    describe('shortcut_grant_update', () => {
      const sendUpdate = async (agent: ReturnType<typeof createMockSocket>, data: unknown) => {
        agent.emit('message', {
          data: JSON.stringify({ type: 'shortcut_grant_update', from: 'agent', data }),
        });
        await tick();
        return agent.sent().find(message => message.type === 'shortcut_grant_update_ack');
      };

      it('requires agent room metadata and a complete update', async () => {
        const room = new SessionManagerDO(createMockState('session-1'), {} as Env);
        const anonymous = createMockSocket();
        await room.addRelaySocket('session-1', anonymous as unknown as WebSocket);
        expect(
          await sendUpdate(anonymous, { state: 'active', grant: activeGrant() })
        ).toMatchObject({
          ok: false,
          code: 'agent_room_unavailable',
        });

        const agent = createMockSocket();
        await room.addRelaySocket('session-1', agent as unknown as WebSocket, {
          deviceId,
          agentIdentityPublicKey: publicKey,
        });
        expect(await sendUpdate(agent, { state: 'paused', grant: activeGrant() })).toMatchObject({
          ok: false,
          code: 'invalid_shortcut_grant_update',
        });
      });

      it('relays registry rejections and failures in the ack', async () => {
        const registry = createRegistry();
        const target: { current: SessionManagerDO | { fetch: () => never } } = {
          current: registry,
        };
        const room = new SessionManagerDO(
          createMockState('session-1'),
          createNamespaceEnv(() => target.current)
        );
        const agent = createMockSocket();
        await room.addRelaySocket('session-1', agent as unknown as WebSocket, {
          deviceId,
          ...enrollmentRegistration(await issueEnrollmentCode(registry)),
        });
        await post(registry, '/registry/agent-offline', { deviceId, sessionId: 'session-1' });

        expect(await sendUpdate(agent, { state: 'active', grant: activeGrant() })).toMatchObject({
          ok: false,
          code: 'device_unavailable',
        });

        agent.send.mockClear();
        target.current = {
          fetch: () => {
            throw new Error('registry down');
          },
        };
        expect(await sendUpdate(agent, { state: 'active', grant: activeGrant() })).toMatchObject({
          ok: false,
          code: 'shortcut_grant_update_sync_failed',
          error: 'registry down',
        });
      });
    });
  });

  describe('shared enrollment fixture', () => {
    const fixture = JSON.parse(
      readFileSync(
        new URL(
          '../../../../packages/shared/protocol/fixtures/agent_enrollment.json',
          import.meta.url
        ),
        'utf8'
      )
    );
    const headers: Record<string, string> = fixture.headers;
    const sessionId: string = fixture.path.slice('/relay/'.length);

    it('lists the v2 transcript fields in order and signs exactly those bytes', () => {
      expect(fixture.transcript.fields).toEqual([
        'cicada-agent-registration-v2',
        headers['x-device-id'],
        sessionId,
        headers['x-agent-identity-public-key'],
        headers['x-agent-registration-timestamp'],
        headers['x-agent-registration-nonce'],
        headers['x-agent-enrollment-code'],
      ]);
      const bytes = transcript(fixture.transcript.fields);
      expect(bytes.toString('base64')).toBe(fixture.transcript.base64);
      const key = createPublicKey({
        key: Buffer.concat([
          ED25519_SPKI_PREFIX,
          Buffer.from(headers['x-agent-identity-public-key'], 'base64'),
        ]),
        format: 'der',
        type: 'spki',
      });
      const signature = Buffer.from(headers['x-agent-registration-signature'], 'base64');
      expect(verifyBytes(null, bytes, key, signature)).toBe(true);
    });

    it('is accepted by the relay as a first registration', async () => {
      const timestamp = Number(headers['x-agent-registration-timestamp']);
      (Date.now as unknown as jest.Mock).mockReturnValue(timestamp);
      const storedValues: Record<string, any> = {
        [enrollmentCodesKey]: [
          {
            codeHash: createHash('sha256')
              .update(headers['x-agent-enrollment-code'])
              .digest('base64url'),
            createdAt: timestamp,
            expiresAt: timestamp + SESSION_CONSTANTS.ENROLLMENT_CODE_TTL_MS,
          },
        ],
      };
      const registry = createRegistry(storedValues);
      await tick();
      const room = new SessionManagerDO(
        createMockState(sessionId),
        createNamespaceEnv(() => registry)
      );

      const response = await room.fetch(
        new Request(`http://session${fixture.path}`, {
          headers: { Upgrade: 'websocket', 'X-Session-ID': sessionId, ...headers },
        })
      );

      expect(response.status).toBe(101);
      expect(storedValues[registryKey]).toEqual([
        expect.objectContaining({
          deviceId: headers['x-device-id'],
          agentIdentityPublicKey: headers['x-agent-identity-public-key'],
        }),
      ]);
      expect(storedValues[enrollmentCodesKey][0].usedAt).toBe(timestamp);
    });
  });
});
