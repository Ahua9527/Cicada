/**
 * Session Manager Durable Object
 * Manages WebSocket sessions using Cloudflare Durable Objects
 */

import {
  SessionInfo,
  Timer,
  RelayTransportMessage,
  RELAY_CLOSE_CODES,
  ShortcutGrantRecord,
  Env,
} from '../../../types';
import { ErrorCode, constantTimeStringEqual, isValidDeviceId } from '@cicada/shared';
import { SESSION_CONSTANTS } from '../../../config/constants';
import {
  createPublicServerErrorResponse,
  enforcePublicServerErrorResponse,
  generateRequestId,
} from '../../../presentation/public-error-response';
import { sanitizeError } from '../../../utils/sensitive-error';
import {
  copyDurableObjectResponse,
  toDurableObjectRequest,
} from '../../cloudflare/worker-fetch-adapter';
import {
  methodNotAllowed,
  extractShortcutToken,
  normalizeShortcutGrant,
  parseShortcutCommandPayload,
  readJsonObject,
  shortcutErrorResponse,
  shortcutFailureStatus,
} from './session-manager.logic';

type DeviceRegistryRecord = {
  deviceId: string;
  connected: boolean;
  liveSessionId?: string;
  agentIdentityPublicKey?: string;
  shortcutGrants?: ShortcutGrantRecord[];
  connectedAt?: number;
  lastPing?: number;
  lastSeen: number;
  uptime?: number;
  sessionId?: string;
  ipAddress?: string;
  userAgent?: string;
};

type RelayRoomInfo = {
  sessionId: string;
  deviceId?: string;
  agentIdentityPublicKey?: string;
};

/** 一次性注册码只存 SHA-256 哈希，明文只在签发响应里出现一次。 */
type EnrollmentCodeRecord = {
  codeHash: string;
  createdAt: number;
  expiresAt: number;
  usedAt?: number;
};

const ENROLLMENT_CODE_FAILURES = {
  agent_enrollment_code_required: {
    status: 401,
    error: 'Agent enrollment code is required for an unbound device.',
  },
  agent_enrollment_code_invalid: { status: 403, error: 'Agent enrollment code is invalid.' },
  agent_enrollment_code_expired: { status: 401, error: 'Agent enrollment code has expired.' },
  agent_enrollment_code_used: { status: 409, error: 'Agent enrollment code was already used.' },
} as const;

type EnrollmentCodeFailure = keyof typeof ENROLLMENT_CODE_FAILURES;

type PendingShortcutCommand = {
  resolve: (response: Response) => void;
  timer: Timer;
  clientRequestId: string;
  command: string;
  dispatchedAt: number;
};

export interface SessionManagerOptions {
  sessionTimeout?: number;
  cleanupInterval?: number;
  agentAbsenceGraceMs?: number;
  shortcutCommandTimeoutMs?: number;
}

export class SessionManagerDO {
  private sessionInfo: Map<string, SessionInfo> = new Map();
  private registryDevices: Map<string, DeviceRegistryRecord> = new Map();
  private enrollmentCodes: EnrollmentCodeRecord[] = [];
  private relaySockets: Map<'agent', WebSocket> = new Map();
  private relayRoomInfo: RelayRoomInfo | null = null;
  private agentAbsenceTimer: Timer | null = null;
  private agentAbsentSince: number | null = null;
  private pendingShortcutCommands: Map<string, PendingShortcutCommand> = new Map();
  private usedRegistrationNonces: Map<string, number> = new Map();
  private options: Required<SessionManagerOptions>;
  private cleanupTimer: Timer | null = null;
  private saveInFlight = false;
  private saveDirty = false;

  constructor(
    private state: DurableObjectState,
    private env: Env,
    options: SessionManagerOptions = {}
  ) {
    this.options = {
      sessionTimeout: options.sessionTimeout ?? SESSION_CONSTANTS.TIMEOUT,
      cleanupInterval: options.cleanupInterval ?? SESSION_CONSTANTS.CLEANUP_INTERVAL,
      agentAbsenceGraceMs: options.agentAbsenceGraceMs ?? SESSION_CONSTANTS.AGENT_ABSENCE_GRACE_MS,
      shortcutCommandTimeoutMs:
        options.shortcutCommandTimeoutMs ?? SESSION_CONSTANTS.SHORTCUT_COMMAND_TIMEOUT_MS,
    };

    this.state.blockConcurrencyWhile(async () => {
      await this.loadSessions();
      this.startCleanupTimer();
    });
  }

  /**
   * Load sessions from persistent storage
   */
  private async loadSessions(): Promise<void> {
    try {
      const sessionData = await this.state.storage.get<SessionInfo[]>(
        SESSION_CONSTANTS.STORAGE_KEYS.SESSIONS
      );
      if (sessionData) {
        sessionData.forEach(info => {
          if (!info) {
            return;
          }
          const deviceKey = info.deviceId ?? this.state.id.toString();
          const normalized = this.normalizeSessionInfo(deviceKey, info);
          this.sessionInfo.set(deviceKey, normalized);
        });
      }

      const registryData = await this.state.storage.get<DeviceRegistryRecord[]>(
        SESSION_CONSTANTS.STORAGE_KEYS.DEVICE_REGISTRY
      );
      if (registryData) {
        registryData.forEach(record => {
          if (record?.deviceId) {
            this.registryDevices.set(record.deviceId, record);
          }
        });
      }

      const enrollmentCodes = await this.state.storage.get<EnrollmentCodeRecord[]>(
        SESSION_CONSTANTS.STORAGE_KEYS.ENROLLMENT_CODES
      );
      if (enrollmentCodes) {
        this.enrollmentCodes = enrollmentCodes;
      }

    } catch (error) {
      this.logStructured('error', 'Failed to load session data', { error });
    }
  }

  /**
   * Save sessions to persistent storage
   *
   * H9: 单写合并。一次 storage.put 进行期间，新的落盘请求只标记 saveDirty，
   * 不再各自触发一次完整 put；落盘完成后若 dirty 则尾随一次补写。
   */
  private async saveSessions(): Promise<void> {
    if (this.saveInFlight) {
      this.saveDirty = true;
      return;
    }
    this.saveInFlight = true;
    try {
      const sessions = Array.from(this.sessionInfo.values()).map(info =>
        this.normalizeSessionInfo(info.deviceId ?? this.state.id.toString(), info)
      );
      await this.state.storage.put({
        [SESSION_CONSTANTS.STORAGE_KEYS.SESSIONS]: sessions,
      });
    } catch (error) {
      this.logStructured('error', 'Failed to save session data', { error });
    } finally {
      this.saveInFlight = false;
    }
    // 落盘期间到达的变更：尾随一次补写（仍受 in-flight 闸门保护）。
    if (this.saveDirty) {
      this.saveDirty = false;
      this.state.waitUntil(this.saveSessions());
    }
  }

  private async saveRegistryDevices(): Promise<void> {
    await this.state.storage.put(
      SESSION_CONSTANTS.STORAGE_KEYS.DEVICE_REGISTRY,
      Array.from(this.registryDevices.values())
    );
  }

  private async saveEnrollmentCodes(): Promise<void> {
    await this.state.storage.put(
      SESSION_CONSTANTS.STORAGE_KEYS.ENROLLMENT_CODES,
      this.enrollmentCodes
    );
  }

  /**
   * Start cleanup timer
   */
  private startCleanupTimer(): void {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer);
    }

    this.cleanupTimer = setInterval(() => {
      this.cleanupInactiveSessions();
    }, this.options.cleanupInterval);
    // Cloudflare Workers 无 unref，Node 测试运行时需要它让事件循环退出；可选调用兼容两者。
    (this.cleanupTimer as { unref?: () => void }).unref?.();
  }

  private clearAgentAbsenceTimer(): void {
    if (this.agentAbsenceTimer) {
      clearTimeout(this.agentAbsenceTimer);
      this.agentAbsenceTimer = null;
    }
    this.agentAbsentSince = null;
  }

  private scheduleAgentAbsenceTimeout(deviceId: string, sessionId: string): void {
    this.clearAgentAbsenceTimer();
    this.agentAbsentSince = Date.now();
    this.agentAbsenceTimer = setTimeout(() => {
      if (this.relaySockets.has('agent')) {
        this.clearAgentAbsenceTimer();
        return;
      }

      this.agentAbsenceTimer = null;
      this.agentAbsentSince = null;
      this.state.waitUntil(this.syncRelayRegistryAgentOffline(deviceId, sessionId));
    }, this.options.agentAbsenceGraceMs);
    // 同上：可选调用 unref，避免 Node 测试进程被挂起。
    (this.agentAbsenceTimer as { unref?: () => void }).unref?.();
  }

  async addRelaySocket(
    sessionId: string,
    ws: WebSocket,
    metadata: {
      deviceId?: string;
      agentIdentityPublicKey?: string;
      enrollmentCode?: string;
      registrationTimestamp?: number;
      registrationNonce?: string;
      registrationSignature?: string;
    } = {}
  ): Promise<{ success: boolean; error?: string; code?: string }> {
    const now = Date.now();
    if (metadata.deviceId && metadata.agentIdentityPublicKey) {
      const registration = await this.syncRelayRegistryAgentOnline({
        deviceId: metadata.deviceId,
        sessionId,
        agentIdentityPublicKey: metadata.agentIdentityPublicKey,
        enrollmentCode: metadata.enrollmentCode,
        registrationTimestamp: metadata.registrationTimestamp,
        registrationNonce: metadata.registrationNonce,
        registrationSignature: metadata.registrationSignature,
        lastSeen: now,
      });
      if (!registration.ok) {
        return {
          success: false,
          error: registration.error ?? registration.code ?? 'Agent registration rejected',
          code: registration.code,
        };
      }
    }

    const existing = this.relaySockets.get('agent');
    if (existing && existing !== ws) {
      existing.close(RELAY_CLOSE_CODES.AGENT_REPLACED, 'Previous agent connection replaced');
    }

    this.clearAgentAbsenceTimer();

    this.relaySockets.set('agent', ws);
    this.relayRoomInfo = {
      ...(this.relayRoomInfo ?? { sessionId }),
      sessionId,
      ...(metadata.deviceId ? { deviceId: metadata.deviceId } : {}),
      ...(metadata.agentIdentityPublicKey
        ? { agentIdentityPublicKey: metadata.agentIdentityPublicKey }
        : {}),
    };

    ws.addEventListener('message', event => {
      this.handleRelayMessage(ws, event);
    });

    ws.addEventListener('close', () => {
      if (this.relaySockets.get('agent') !== ws) {
        return;
      }
      this.relaySockets.delete('agent');
      if (this.relayRoomInfo?.deviceId) {
        this.rejectPendingShortcutCommands(ErrorCode.AGENT_UNAVAILABLE, 'Agent disconnected.');
        this.scheduleAgentAbsenceTimeout(this.relayRoomInfo.deviceId, sessionId);
      }
    });

    ws.addEventListener('error', error => {
      this.logStructured('error', 'Relay agent WebSocket error', { error });
    });

    return { success: true };
  }

  /**
   * Cleanup inactive sessions
   */
  async cleanupInactiveSessions(): Promise<{ cleaned: number; remaining: number }> {
    const now = Date.now();
    const timeout = this.options.sessionTimeout;
    let cleanedCount = 0;

    for (const [deviceId, info] of this.sessionInfo) {
      const lastPing = info.lastPing ?? info.lastActivity ?? info.connectedAt ?? now;
      if (now - lastPing > timeout) {
        this.sessionInfo.delete(deviceId);
        cleanedCount++;
      }
    }

    await this.saveSessions();
    return {
      cleaned: cleanedCount,
      remaining: this.sessionInfo.size,
    };
  }

  private normalizeSessionInfo(deviceId: string, info: Partial<SessionInfo>): SessionInfo {
    const now = Date.now();
    const connectedAt = info.connectedAt ?? info.createdAt ?? now;
    const lastPing = info.lastPing ?? info.lastActivity ?? connectedAt;
    return {
      sessionId: info.sessionId ?? `${deviceId}-${connectedAt}`,
      deviceId: info.deviceId ?? deviceId,
      isActive: info.isActive ?? true,
      createdAt: info.createdAt ?? connectedAt,
      lastActivity: info.lastActivity ?? lastPing,
      connectedAt,
      lastPing,
      metadata: info.metadata,
    };
  }

  private getDeviceId(fallback?: string | null): string {
    return fallback ?? this.state.id.name ?? this.state.id.toString();
  }

  private parseOptionalNumber(value: string | null): number | undefined {
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : undefined;
  }

  private handleRelayMessage(ws: WebSocket, event: MessageEvent): void {
    if (typeof event.data !== 'string') {
      return;
    }

    let message: RelayTransportMessage | null = null;
    try {
      message = JSON.parse(event.data) as RelayTransportMessage;
    } catch {
      this.sendRelayError(ws, 'invalid_json', 'Relay transport messages must be JSON.');
      return;
    }

    if (message.type === 'ping') {
      ws.send(
        JSON.stringify({
          type: 'pong',
          id: message.id,
          sent_at: Date.now(),
        })
      );
      return;
    }

    if (message.type === 'shortcut_grant_update') {
      this.state.waitUntil(this.applyShortcutGrantUpdate(message, ws));
      return;
    }

    if (message.type === 'shortcut_result') {
      this.handleShortcutResult(message);
      return;
    }
  }

  private sendRelayError(ws: WebSocket, code: string, error: string): void {
    ws.send(
      JSON.stringify({
        type: 'error',
        code,
        error,
        sent_at: Date.now(),
      })
    );
  }

  private async applyShortcutGrantUpdate(message: RelayTransportMessage, ws: WebSocket): Promise<void> {
    if (!this.relayRoomInfo?.deviceId) {
      this.sendShortcutGrantUpdateAck(ws, {
        ok: false,
        code: 'agent_room_unavailable',
        error: 'Agent room metadata is unavailable.',
      });
      return;
    }

    const data = 'data' in message && typeof message.data === 'object' ? message.data : {};
    const state = data?.state === 'active' || data?.state === 'revoked' ? data.state : undefined;
    const grant = typeof data?.grant === 'object' ? (data.grant as Partial<ShortcutGrantRecord>) : undefined;
    if (!state || !grant?.grantId) {
      this.sendShortcutGrantUpdateAck(ws, {
        ok: false,
        code: 'invalid_shortcut_grant_update',
        error: 'Shortcut grant update is missing required fields.',
      });
      return;
    }

    const result = await this.syncRelayRegistryShortcutGrantUpdate({
      deviceId: this.relayRoomInfo.deviceId,
      sessionId: this.relayRoomInfo.sessionId,
      state,
      grant,
      lastSeen: Date.now(),
    });

    this.sendShortcutGrantUpdateAck(ws, result);
  }

  private handleShortcutResult(message: RelayTransportMessage): void {
    const data = 'data' in message && typeof message.data === 'object' ? message.data : {};
    const dispatchId = typeof data?.requestId === 'string' ? data.requestId : message.id;
    if (!dispatchId) {
      return;
    }

    const pending = this.pendingShortcutCommands.get(dispatchId);
    if (!pending) {
      return;
    }
    clearTimeout(pending.timer);
    this.pendingShortcutCommands.delete(dispatchId);

    const ok = data?.ok === true;
    const latencyMs = Date.now() - pending.dispatchedAt;
    const rawResultData =
      typeof data?.resultData === 'object' && data.resultData !== null
        ? data.resultData
        : typeof data?.data === 'object' && data.data !== null
          ? data.data
          : undefined;
    // 设备往返时延（relay 发出到收到结果）合并进 data，供快捷指令展示 ping 值。
    const resultData = { ...(rawResultData as Record<string, unknown>), latency_ms: latencyMs };
    const body = {
      ok,
      request_id: pending.clientRequestId,
      command: typeof data?.command === 'string' ? data.command : pending.command,
      success: data?.success === true,
      message: typeof data?.message === 'string' ? data.message : undefined,
      data: resultData,
      latency_ms: latencyMs,
      code: typeof data?.code === 'string' ? data.code : undefined,
      error: typeof data?.error === 'string' ? data.error : undefined,
      timestamp: Date.now(),
    };
    const status = ok ? 200 : shortcutFailureStatus(body.code);
    pending.resolve(this.jsonResponse(body, { status }));
  }

  private rejectPendingShortcutCommands(code: string, error: string): void {
    for (const pending of this.pendingShortcutCommands.values()) {
      clearTimeout(pending.timer);
      pending.resolve(
        this.shortcutError(
          code,
          error,
          shortcutFailureStatus(code),
          pending.clientRequestId,
          pending.command
        )
      );
    }
    this.pendingShortcutCommands.clear();
  }

  private sendShortcutGrantUpdateAck(
    ws: WebSocket,
    payload: {
      ok: boolean;
      grantId?: string;
      state?: 'active' | 'revoked';
      code?: string;
      error?: string;
    }
  ): void {
    ws.send(
      JSON.stringify({
        type: 'shortcut_grant_update_ack',
        ok: payload.ok,
        grantId: payload.grantId,
        state: payload.state,
        code: payload.code,
        error: payload.error,
        sent_at: Date.now(),
      })
    );
  }

  private async syncRelayRegistryAgentOnline(payload: {
    deviceId: string;
    sessionId: string;
    agentIdentityPublicKey: string;
    enrollmentCode?: string;
    registrationTimestamp?: number;
    registrationNonce?: string;
    registrationSignature?: string;
    lastSeen: number;
  }): Promise<{ ok: boolean; error?: string; code?: string }> {
    if (this.getDeviceId() === SESSION_CONSTANTS.REGISTRY_DO_NAME) {
      return { ok: true };
    }
    if (
      typeof this.env?.CICADA_SESSIONS?.idFromName !== 'function' ||
      typeof this.env?.CICADA_SESSIONS?.get !== 'function'
    ) {
      return { ok: true };
    }

    try {
      const registry = this.env.CICADA_SESSIONS.get(
        this.env.CICADA_SESSIONS.idFromName(SESSION_CONSTANTS.REGISTRY_DO_NAME)
      );
      const response = await registry.fetch(
        toDurableObjectRequest(new Request('http://registry/registry/agent-online', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        }))
      );
      const body = (await response.json()) as { ok?: boolean; error?: string; code?: string };
      if (!response.ok || body.ok === false) {
        return {
          ok: false,
          error: body.error,
          code: body.code,
        };
      }
      return { ok: true };
    } catch (error) {
      return {
        ok: false,
        error: error instanceof Error ? error.message : 'Failed to sync agent registry',
        code: 'agent_registry_sync_failed',
      };
    }
  }

  private async syncRelayRegistryShortcutGrantUpdate(payload: {
    deviceId: string;
    sessionId: string;
    state: 'active' | 'revoked';
    grant: Partial<ShortcutGrantRecord>;
    lastSeen: number;
  }): Promise<{
    ok: boolean;
    grantId?: string;
    state?: 'active' | 'revoked';
    error?: string;
    code?: string;
  }> {
    if (this.getDeviceId() === SESSION_CONSTANTS.REGISTRY_DO_NAME) {
      return { ok: true, grantId: payload.grant.grantId, state: payload.state };
    }
    if (
      typeof this.env?.CICADA_SESSIONS?.idFromName !== 'function' ||
      typeof this.env?.CICADA_SESSIONS?.get !== 'function'
    ) {
      return { ok: true, grantId: payload.grant.grantId, state: payload.state };
    }

    try {
      const registry = this.env.CICADA_SESSIONS.get(
        this.env.CICADA_SESSIONS.idFromName(SESSION_CONSTANTS.REGISTRY_DO_NAME)
      );
      const response = await registry.fetch(
        toDurableObjectRequest(new Request('http://registry/registry/shortcut-grant-update', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        }))
      );
      const body = (await response.json()) as {
        ok?: boolean;
        grantId?: string;
        state?: 'active' | 'revoked';
        error?: string;
        code?: string;
      };
      if (!response.ok || body.ok === false) {
        return { ok: false, error: body.error, code: body.code };
      }
      return {
        ok: true,
        grantId: body.grantId ?? payload.grant.grantId,
        state: body.state ?? payload.state,
      };
    } catch (error) {
      return {
        ok: false,
        error: error instanceof Error ? error.message : 'Failed to sync shortcut grant update',
        code: 'shortcut_grant_update_sync_failed',
      };
    }
  }

  private async syncRelayRegistryAgentOffline(deviceId: string, sessionId: string): Promise<void> {
    if (this.getDeviceId() === SESSION_CONSTANTS.REGISTRY_DO_NAME) {
      return;
    }
    if (
      typeof this.env?.CICADA_SESSIONS?.idFromName !== 'function' ||
      typeof this.env?.CICADA_SESSIONS?.get !== 'function'
    ) {
      return;
    }
    const registry = this.env.CICADA_SESSIONS.get(
      this.env.CICADA_SESSIONS.idFromName(SESSION_CONSTANTS.REGISTRY_DO_NAME)
    );
    await registry.fetch(
      toDurableObjectRequest(new Request('http://registry/registry/agent-offline', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ deviceId, sessionId }),
      }))
    );
  }

  private jsonResponse<T>(body: T, init?: ResponseInit): Response {
    return Response.json(body, init);
  }

  private createWebSocketResponse(webSocket: WebSocket): Response {
    try {
      return new Response(null, { status: 101, webSocket });
    } catch (error) {
      if (error instanceof RangeError || String(error).includes('init["status"]')) {
        return new Response(null, { status: 200 });
      }
      throw error;
    }
  }

  private async handleRoomShortcutCommand(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return methodNotAllowed(['POST']);
    }

    const payload = await readJsonObject(request);
    if (!payload) {
      return this.shortcutError(
        ErrorCode.INVALID_SHORTCUT_COMMAND,
        'Shortcut command dispatch body must be a valid JSON object.',
        400
      );
    }
    const clientRequestId = typeof payload.requestId === 'string' ? payload.requestId : '';
    const targetDeviceId = typeof payload.deviceId === 'string' ? payload.deviceId : '';
    const command = typeof payload.command === 'string' ? payload.command : '';
    const grantId = typeof payload.grantId === 'string' ? payload.grantId : '';
    const params =
      payload.params && typeof payload.params === 'object' && !Array.isArray(payload.params)
        ? (payload.params as Record<string, unknown>)
        : undefined;
    if (!clientRequestId || !command || !grantId) {
      return this.shortcutError(
        ErrorCode.INVALID_SHORTCUT_COMMAND,
        'Shortcut command dispatch is missing required fields.',
        400,
        clientRequestId,
        command
      );
    }

    if (
      targetDeviceId &&
      this.relayRoomInfo?.deviceId &&
      targetDeviceId !== this.relayRoomInfo.deviceId
    ) {
      return this.shortcutError(
        ErrorCode.AGENT_UNAVAILABLE,
        'Shortcut command target does not match this agent room.',
        503,
        clientRequestId,
        command
      );
    }

    const agent = this.relaySockets.get('agent');
    if (!agent) {
      return this.shortcutError(
        ErrorCode.AGENT_UNAVAILABLE,
        'Agent is not online.',
        503,
        clientRequestId,
        command
      );
    }

    const dispatchId = this.createShortcutDispatchId();
    return await new Promise<Response>(resolve => {
      const timer = setTimeout(() => {
        this.pendingShortcutCommands.delete(dispatchId);
        resolve(
          this.shortcutError(
            ErrorCode.COMMAND_TIMEOUT,
            'Agent did not return a shortcut result before timeout.',
            504,
            clientRequestId,
            command
          )
        );
      }, this.options.shortcutCommandTimeoutMs);
      // 同上：可选调用 unref，避免 Node 测试进程被挂起。
      (timer as { unref?: () => void }).unref?.();
      this.pendingShortcutCommands.set(dispatchId, {
        resolve,
        timer,
        clientRequestId,
        command,
        dispatchedAt: Date.now(),
      });

      try {
        agent.send(
          JSON.stringify({
            type: 'shortcut_command',
            id: dispatchId,
            sent_at: Date.now(),
            data: {
              requestId: dispatchId,
              grantId,
              command,
              ...(params ? { params } : {}),
            },
          })
        );
      } catch {
        clearTimeout(timer);
        this.pendingShortcutCommands.delete(dispatchId);
        resolve(
          this.shortcutError(
            ErrorCode.AGENT_UNAVAILABLE,
            'Failed to send shortcut command to agent.',
            503,
            clientRequestId,
            command
          )
        );
      }
    });
  }

  private async handleRegistryAgentOnline(request: Request, requestId: string): Promise<Response> {
    if (request.method !== 'POST') {
      return methodNotAllowed(['POST']);
    }

    const payload = (await request.json()) as {
      deviceId?: string;
      sessionId?: string;
      agentIdentityPublicKey?: string;
      enrollmentCode?: string;
      registrationTimestamp?: number;
      registrationNonce?: string;
      registrationSignature?: string;
      lastSeen?: number;
    };

    if (!payload.deviceId || !payload.sessionId || !payload.agentIdentityPublicKey) {
      return this.jsonResponse(
        {
          ok: false,
          error: 'Agent online registration requires deviceId, sessionId, and identity key.',
          code: 'invalid_agent_registration',
        },
        { status: 400 }
      );
    }

    const existing = this.registryDevices.get(payload.deviceId);
    if (existing?.agentIdentityPublicKey && existing.agentIdentityPublicKey !== payload.agentIdentityPublicKey) {
      return this.agentIdentityMismatchResponse();
    }
    // 未绑定的 deviceId 只能凭有效的一次性注册码首次登记，不再“首次见到即信任”。
    if (!existing?.agentIdentityPublicKey && !payload.enrollmentCode) {
      return this.rejectEnrollment('agent_enrollment_code_required', requestId);
    }

    const now = Date.now();
    if (
      !payload.registrationTimestamp ||
      !payload.registrationNonce ||
      !payload.registrationSignature
    ) {
      return this.jsonResponse(
        {
          ok: false,
          error: 'Agent registration signature is required.',
          code: 'agent_registration_signature_required',
        },
        { status: 401 }
      );
    }
    if (
      Math.abs(now - Number(payload.registrationTimestamp)) >
      SESSION_CONSTANTS.AGENT_REGISTRATION_SKEW
    ) {
      return this.jsonResponse(
        {
          ok: false,
          error: 'Agent registration request expired.',
          code: 'agent_registration_expired',
        },
        { status: 401 }
      );
    }
    this.pruneUsedRegistrationNonces(now);
    const nonceKey = `${payload.deviceId}|agent|${payload.registrationNonce}`;
    if (this.usedRegistrationNonces.has(nonceKey)) {
      this.logStructured('warn', 'Agent registration replay rejected', {
        request_id: requestId,
        security_event: 'agent_registration_replayed',
        status: 409,
        do_operation: 'registry_agent_online',
      });
      return this.jsonResponse(
        {
          ok: false,
          error: 'Agent registration request was already used.',
          code: 'agent_registration_replayed',
        },
        { status: 409 }
      );
    }
    // 带注册码时签名内容是 v2（含注册码），否则是 v1；已绑定设备不带码时与原流程一致。
    const transcript = this.buildAgentRegistrationTranscript({
      deviceId: payload.deviceId,
      sessionId: payload.sessionId,
      agentIdentityPublicKey: payload.agentIdentityPublicKey,
      timestamp: Number(payload.registrationTimestamp),
      nonce: payload.registrationNonce,
      enrollmentCode: payload.enrollmentCode,
    });
    // 已绑定时这就是绑定的那把公钥；未绑定时用它验签，证明登记方持有对应私钥。
    const signatureValid = await this.verifyEd25519Signature(
      payload.agentIdentityPublicKey,
      transcript,
      payload.registrationSignature
    );
    if (!signatureValid) {
      return this.jsonResponse(
        {
          ok: false,
          error: 'Agent registration signature is invalid.',
          code: 'invalid_agent_registration_signature',
        },
        { status: 403 }
      );
    }
    // 过期锚定到所声明时间戳的最晚可接受时间，防止未来时间戳在条目过期后重放。
    this.usedRegistrationNonces.set(
      nonceKey,
      Number(payload.registrationTimestamp) + SESSION_CONSTANTS.AGENT_REGISTRATION_SKEW
    );
    const codeHash = payload.enrollmentCode
      ? await this.sha256Base64Url(payload.enrollmentCode)
      : undefined;

    // 上面的 await 期间可能有并发登记改了绑定，按最新状态决定是否核销注册码。
    const current = this.registryDevices.get(payload.deviceId);
    if (
      current?.agentIdentityPublicKey &&
      current.agentIdentityPublicKey !== payload.agentIdentityPublicKey
    ) {
      return this.agentIdentityMismatchResponse();
    }
    // 已绑定到同一把公钥的设备带码重试（比如没收到上次成功的响应）时不再核销注册码。
    const enrolling = !current?.agentIdentityPublicKey;
    if (enrolling) {
      const failure = codeHash
        ? this.claimEnrollmentCode(codeHash, now)
        : 'agent_enrollment_code_required';
      if (failure) {
        return this.rejectEnrollment(failure, requestId);
      }
    }

    const record: DeviceRegistryRecord = {
      ...(current ?? {
        deviceId: payload.deviceId,
        lastSeen: payload.lastSeen ?? now,
        connected: false,
      }),
      deviceId: payload.deviceId,
      connected: true,
      liveSessionId: payload.sessionId,
      sessionId: payload.sessionId,
      agentIdentityPublicKey: payload.agentIdentityPublicKey,
      connectedAt: current?.connectedAt ?? now,
      lastPing: now,
      lastSeen: payload.lastSeen ?? now,
    };

    this.registryDevices.set(payload.deviceId, record);
    if (enrolling) {
      // 绑定和注册码作废放在同一次 put 里写入，不会只落一半。
      await this.state.storage.put({
        [SESSION_CONSTANTS.STORAGE_KEYS.DEVICE_REGISTRY]: Array.from(this.registryDevices.values()),
        [SESSION_CONSTANTS.STORAGE_KEYS.ENROLLMENT_CODES]: this.enrollmentCodes,
      });
      this.logStructured('info', 'Agent enrolled with a one-time code', {
        request_id: requestId,
        security_event: 'agent_enrolled',
        do_operation: 'registry_agent_online',
      });
    } else {
      await this.saveRegistryDevices();
    }

    return this.jsonResponse({
      ok: true,
      success: true,
      device: record,
    });
  }

  private agentIdentityMismatchResponse(): Response {
    return this.jsonResponse(
      {
        ok: false,
        error: 'Agent identity key does not match first-seen binding.',
        code: 'agent_identity_mismatch',
      },
      { status: 403 }
    );
  }

  /** 核对注册码并作废（只改内存，由调用方落盘）；失败时返回具体的错误码。 */
  private claimEnrollmentCode(codeHash: string, now: number): EnrollmentCodeFailure | null {
    // 与快捷指令令牌一致：逐条用恒定时间比较哈希。
    const record = this.enrollmentCodes.find(candidate =>
      constantTimeStringEqual(candidate.codeHash, codeHash)
    );
    if (!record) {
      return 'agent_enrollment_code_invalid';
    }
    if (record.usedAt) {
      return 'agent_enrollment_code_used';
    }
    if (now >= record.expiresAt) {
      return 'agent_enrollment_code_expired';
    }
    record.usedAt = now;
    return null;
  }

  private rejectEnrollment(failure: EnrollmentCodeFailure, requestId: string): Response {
    const { status, error } = ENROLLMENT_CODE_FAILURES[failure];
    // 没登记的 Mac 会按退避一直重连，缺码是预期状态，不记安全事件；
    // 码无效、过期或已用才记，便于发现猜码。日志里不放注册码和 deviceId。
    if (failure !== 'agent_enrollment_code_required') {
      this.logStructured('warn', 'Agent enrollment rejected', {
        request_id: requestId,
        security_event: 'agent_enrollment_rejected',
        reason: failure,
        status,
        do_operation: 'registry_agent_online',
      });
    }
    return this.jsonResponse({ ok: false, error, code: failure }, { status });
  }

  private async handleRegistryAgentOffline(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return methodNotAllowed(['POST']);
    }

    const payload = (await request.json()) as { deviceId?: string; sessionId?: string };
    if (!payload.deviceId) {
      return this.jsonResponse({ ok: false, error: 'Missing deviceId' }, { status: 400 });
    }

    const record = this.registryDevices.get(payload.deviceId);
    if (record && (!payload.sessionId || record.liveSessionId === payload.sessionId)) {
      this.registryDevices.set(payload.deviceId, {
        ...record,
        connected: false,
        lastSeen: Date.now(),
      });
      await this.saveRegistryDevices();
    }

    return this.jsonResponse({ ok: true, success: true });
  }

  private async handleRegistryShortcutGrantUpdate(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return methodNotAllowed(['POST']);
    }

    const payload = (await request.json()) as {
      deviceId?: string;
      sessionId?: string;
      state?: 'active' | 'revoked';
      grant?: Partial<ShortcutGrantRecord>;
      lastSeen?: number;
    };

    if (!payload.deviceId || !payload.sessionId || !payload.grant?.grantId) {
      return this.jsonResponse(
        {
          ok: false,
          error: 'Shortcut grant update is missing required fields.',
          code: 'invalid_shortcut_grant_update',
        },
        { status: 400 }
      );
    }

    const now = Date.now();
    const record = this.registryDevices.get(payload.deviceId);
    if (!record?.connected || record.liveSessionId !== payload.sessionId) {
      return this.jsonResponse(
        {
          ok: false,
          error: 'Shortcut grant target is not online.',
          code: 'device_unavailable',
        },
        { status: 404 }
      );
    }

    const grants = record.shortcutGrants ?? [];
    if (payload.state === 'revoked') {
      const updated = grants.map(grant =>
        grant.grantId === payload.grant?.grantId
          ? { ...grant, revokedAt: payload.grant?.revokedAt ?? now, updatedAt: now }
          : grant
      );
      this.registryDevices.set(payload.deviceId, {
        ...record,
        shortcutGrants: updated,
        lastPing: now,
        lastSeen: payload.lastSeen ?? now,
      });
      await this.saveRegistryDevices();
      return this.jsonResponse({
        ok: true,
        success: true,
        grantId: payload.grant.grantId,
        state: 'revoked',
      });
    }

    const grant = normalizeShortcutGrant(payload.deviceId, payload.grant, now);
    if (!grant) {
      return this.jsonResponse(
        {
          ok: false,
          error: 'Shortcut grant update contains invalid grant metadata.',
          code: 'invalid_shortcut_grant_update',
        },
        { status: 400 }
      );
    }

    const nextGrants = grants
      .filter(existing => existing.grantId !== grant.grantId)
      .concat(grant);
    this.registryDevices.set(payload.deviceId, {
      ...record,
      shortcutGrants: nextGrants,
      lastPing: now,
      lastSeen: payload.lastSeen ?? now,
    });
    await this.saveRegistryDevices();

    return this.jsonResponse({
      ok: true,
      success: true,
      grantId: grant.grantId,
      state: 'active',
    });
  }

  private async handleShortcutCommand(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return methodNotAllowed(['POST']);
    }

    const token = extractShortcutToken(request);
    if (!token) {
      return this.shortcutError(
        ErrorCode.INVALID_TOKEN,
        'Shortcut token is missing or malformed.',
        401
      );
    }

    const payload = await readJsonObject(request);
    if (!payload) {
      return this.shortcutError(
        ErrorCode.INVALID_SHORTCUT_COMMAND,
        'Shortcut command body must be a valid JSON object.',
        400
      );
    }
    const { deviceId, command, requestId, params } = parseShortcutCommandPayload(
      payload,
      `shortcut-${this.createRandomToken(12)}`
    );

    if (!deviceId || !command) {
      return this.shortcutError(
        ErrorCode.INVALID_SHORTCUT_COMMAND,
        'Shortcut command requires device_id and command.',
        400,
        requestId,
        command
      );
    }

    const tokenHash = await this.sha256Base64Url(token);
    const record = this.registryDevices.get(deviceId);
    // M9: 使用恒定时间字符串比较替代 ===，避免 tokenHash 比较的时序侧信道。
    const grant = record?.shortcutGrants?.find(
      candidate =>
        candidate.tokenHash.length === tokenHash.length &&
        constantTimeStringEqual(candidate.tokenHash, tokenHash)
    );
    if (!record || !grant) {
      return this.shortcutError(
        ErrorCode.INVALID_TOKEN,
        'Shortcut token is invalid.',
        401,
        requestId,
        command
      );
    }
    if (grant.revokedAt) {
      return this.shortcutError(
        ErrorCode.GRANT_REVOKED,
        'Shortcut grant has been revoked.',
        403,
        requestId,
        command
      );
    }
    if (Date.now() >= grant.expiresAt) {
      return this.shortcutError(
        ErrorCode.GRANT_EXPIRED,
        'Shortcut grant has expired.',
        403,
        requestId,
        command
      );
    }
    if (!grant.allowedCommands.includes(command)) {
      return this.shortcutError(
        ErrorCode.COMMAND_NOT_ALLOWED,
        'Shortcut grant does not allow this command.',
        403,
        requestId,
        command
      );
    }
    if (!record.connected || !record.liveSessionId) {
      return this.shortcutError(
        ErrorCode.AGENT_UNAVAILABLE,
        'Agent is not online.',
        503,
        requestId,
        command
      );
    }
    if (
      typeof this.env?.CICADA_SESSIONS?.idFromName !== 'function' ||
      typeof this.env?.CICADA_SESSIONS?.get !== 'function'
    ) {
      return this.shortcutError(
        ErrorCode.AGENT_UNAVAILABLE,
        'Agent routing is unavailable.',
        503,
        requestId,
        command
      );
    }

    const sessionRoom = this.env.CICADA_SESSIONS.get(
      this.env.CICADA_SESSIONS.idFromName(record.liveSessionId)
    );
    const response = await sessionRoom.fetch(
      toDurableObjectRequest(new Request('http://session/shortcut/command', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          requestId,
          deviceId,
          grantId: grant.grantId,
          command,
          ...(params ? { params } : {}),
        }),
      }))
    );
    return copyDurableObjectResponse(response);
  }

  private async sha256Base64Url(value: string): Promise<string> {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
    return this.base64UrlEncode(new Uint8Array(digest));
  }

  private shortcutError(
    code: string,
    error: string,
    status: number,
    requestId = '',
    command = ''
  ): Response {
    return shortcutErrorResponse(code, error, status, Date.now(), requestId, command);
  }

  private pruneUsedRegistrationNonces(now: number): void {
    for (const [nonce, expiresAt] of this.usedRegistrationNonces.entries()) {
      // > 而非 >=：边界处（now == registrationTimestamp + SKEW）时间戳仍合法，
      // 须保留到边界之后，否则捕获的签名注册能在该精确边界重放。
      if (now > expiresAt) {
        this.usedRegistrationNonces.delete(nonce);
      }
    }
  }

  private createShortcutDispatchId(): string {
    let dispatchId = '';
    do {
      dispatchId = `shortcut-${this.createRandomToken(12)}`;
    } while (this.pendingShortcutCommands.has(dispatchId));
    return dispatchId;
  }

  private createRandomToken(length: number): string {
    const bytes = new Uint8Array(length);
    crypto.getRandomValues(bytes);
    return this.base64UrlEncode(bytes);
  }

  private base64UrlEncode(bytes: Uint8Array): string {
    const binary = Array.from(bytes)
      .map(byte => String.fromCharCode(byte))
      .join('');
    const base64 = globalThis.btoa(binary);
    return base64.replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/g, '');
  }

  private buildAgentRegistrationTranscript(payload: {
    deviceId: string;
    sessionId: string;
    agentIdentityPublicKey: string;
    timestamp: number;
    nonce: string;
    enrollmentCode?: string;
  }): Uint8Array {
    const fields = [
      payload.deviceId,
      payload.sessionId,
      payload.agentIdentityPublicKey,
      String(payload.timestamp),
      payload.nonce,
    ];
    // 带注册码的首次登记用 v2：版本标签不同，v1 和 v2 的签名不能互相顶替。
    return this.buildLengthPrefixedTranscript(
      payload.enrollmentCode
        ? ['cicada-agent-registration-v2', ...fields, payload.enrollmentCode]
        : ['cicada-agent-registration-v1', ...fields]
    );
  }

  private buildLengthPrefixedTranscript(fields: string[]): Uint8Array {
    const encoder = new TextEncoder();
    const chunks: Uint8Array[] = [];
    let totalLength = 0;
    for (const field of fields) {
      const data = encoder.encode(field);
      const length = new Uint8Array(4);
      new DataView(length.buffer).setUint32(0, data.byteLength, false);
      chunks.push(length, data);
      totalLength += length.byteLength + data.byteLength;
    }

    const transcript = new Uint8Array(totalLength);
    let offset = 0;
    for (const chunk of chunks) {
      transcript.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return transcript;
  }

  private async verifyEd25519Signature(
    publicKeyBase64: string,
    transcript: Uint8Array,
    signatureBase64: string
  ): Promise<boolean> {
    try {
      const key = await crypto.subtle.importKey(
        'raw',
        this.base64Decode(publicKeyBase64),
        { name: 'Ed25519' } as AlgorithmIdentifier,
        false,
        ['verify']
      );
      return await crypto.subtle.verify(
        { name: 'Ed25519' } as AlgorithmIdentifier,
        key,
        this.base64Decode(signatureBase64),
        this.toArrayBuffer(transcript)
      );
    } catch {
      return false;
    }
  }

  private toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    const copy = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(copy).set(bytes);
    return copy;
  }

  private base64Decode(value: string): ArrayBuffer {
    const binary = globalThis.atob(value);
    const bytes = Uint8Array.from(binary, char => char.charCodeAt(0));
    const copy = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(copy).set(bytes);
    return copy;
  }

  /// 运维解绑：删除设备的身份绑定，之后设备可以用新注册码、以新密钥重新登记。
  /// worker 侧已校验管理员令牌；DO 不对公网暴露，无需二次鉴权。
  private async handleRegistryAdminResetDevice(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return methodNotAllowed(['POST']);
    }

    let payload: { deviceId?: string };
    try {
      payload = (await request.json()) as { deviceId?: string };
    } catch {
      return this.jsonResponse(
        { ok: false, error: 'Request body must be JSON', code: 'invalid_body' },
        { status: 400 }
      );
    }
    if (!payload.deviceId || !isValidDeviceId(payload.deviceId)) {
      return this.jsonResponse(
        { ok: false, error: 'Valid deviceId is required.', code: 'invalid_device_id' },
        { status: 400 }
      );
    }

    const existed = this.registryDevices.delete(payload.deviceId);
    if (existed) {
      await this.saveRegistryDevices();
    }
    return this.jsonResponse({ ok: true, deviceId: payload.deviceId, existed });
  }

  /// 签发一次性注册码：注册表只存哈希，明文只在这次响应里返回。
  /// 与 admin-reset-device 相同，管理员令牌已在 worker 侧校验。
  private async handleRegistryAdminEnrollmentCode(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return methodNotAllowed(['POST']);
    }

    const now = Date.now();
    const expiresAt = now + SESSION_CONSTANTS.ENROLLMENT_CODE_TTL_MS;
    const enrollmentCode = `cicada_enroll_${this.createRandomToken(16)}`;
    const codeHash = await this.sha256Base64Url(enrollmentCode);
    this.enrollmentCodes.push({ codeHash, createdAt: now, expiresAt });
    this.pruneEnrollmentCodes(now);
    await this.saveEnrollmentCodes();
    return this.jsonResponse({ ok: true, enrollmentCode, expiresAt }, { status: 201 });
  }

  /** 删掉过期超过保留期的记录，并且只留最新的若干条，控制注册表存储大小。 */
  private pruneEnrollmentCodes(now: number): void {
    this.enrollmentCodes = this.enrollmentCodes
      .filter(record => now <= record.expiresAt + SESSION_CONSTANTS.ENROLLMENT_CODE_RETENTION_MS)
      .slice(-SESSION_CONSTANTS.MAX_ENROLLMENT_CODES);
  }

  private handleRegistryDevices(request: Request): Response {
    if (request.method !== 'GET') {
      return methodNotAllowed(['GET']);
    }

    const now = Date.now();
    // H8: 默认从对外响应中移除 ipAddress/userAgent 等敏感字段，仅暴露
    // deviceId/在线状态/最后心跳时间等非敏感字段。对外的 /devices 由 worker 校验管理员令牌。
    const devices = Array.from(this.registryDevices.values())
      .sort((left, right) => right.lastSeen - left.lastSeen)
      .map(device => ({
        deviceId: device.deviceId,
        connected: device.connected,
        connectedAt: device.connectedAt,
        lastPing: device.lastPing ?? device.lastSeen,
        uptime: device.connected && device.connectedAt ? now - device.connectedAt : undefined,
      }));
    return this.jsonResponse({
      success: true,
      devices,
      total: devices.length,
      active: devices.filter(device => device.connected).length,
    });
  }

  private handleRegistryStatus(request: Request): Response {
    if (request.method !== 'GET') {
      return methodNotAllowed(['GET']);
    }

    const devices = Array.from(this.registryDevices.values());
    const activeDevices = devices.filter(device => device.connected).length;
    return this.jsonResponse({
      success: true,
      totalDevices: devices.length,
      activeDevices,
      totalSessions: devices.length,
      activeConnections: activeDevices,
    });
  }

  private handleOptions(): Response {
    return new Response(null, { status: 204 });
  }

  private async handleWebSocketUpgrade(request: Request, requestId: string): Promise<Response> {
    try {
      // Create WebSocketPair in Durable Object
      // eslint-disable-next-line no-undef
      const pair = new WebSocketPair();
      const [client, server] = [pair[0], pair[1]];

      // Accept the WebSocket connection
      server.accept();

      const sessionId = request.headers.get('X-Session-ID') ?? this.getDeviceId();
      const result = await this.addRelaySocket(sessionId, server, {
        deviceId: request.headers.get('X-Device-ID') ?? undefined,
        agentIdentityPublicKey: request.headers.get('X-Agent-Identity-Public-Key') ?? undefined,
        enrollmentCode: request.headers.get('X-Agent-Enrollment-Code') ?? undefined,
        registrationTimestamp: this.parseOptionalNumber(
          request.headers.get('X-Agent-Registration-Timestamp')
        ),
        registrationNonce: request.headers.get('X-Agent-Registration-Nonce') ?? undefined,
        registrationSignature: request.headers.get('X-Agent-Registration-Signature') ?? undefined,
      });

      if (!result.success) {
        const closeCode =
          result.error === 'Agent session not available'
            ? RELAY_CLOSE_CODES.AGENT_UNAVAILABLE
            : 1013;
        server.close(closeCode, result.error ?? 'Session limit reached');
        return this.jsonResponse(
          {
            success: false,
            error: result.error ?? 'Failed to add session',
            code: result.code,
          },
          { status: 429 }
        );
      }

      // Return the client WebSocket to the original requester
      return this.createWebSocketResponse(client);
    } catch (error) {
      this.logServerError('WebSocket upgrade failed', requestId, 'websocket_upgrade', error);
      return createPublicServerErrorResponse(requestId);
    }
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const requestId = request.headers.get('X-Request-ID') ?? generateRequestId();

    if (request.method === 'OPTIONS') {
      return this.handleOptions();
    }

    // Check if this is a WebSocket upgrade request
    const upgrade = request.headers.get('Upgrade');
    if (upgrade && upgrade.toLowerCase().includes('websocket')) {
      if (!url.pathname.startsWith('/relay/')) {
        return this.jsonResponse(
          {
            success: false,
            error: 'Not found',
            path: url.pathname,
          },
          { status: 404 }
        );
      }
      return await this.handleWebSocketUpgrade(request, requestId);
    }

    try {
      let response: Response;
      switch (url.pathname) {
        case '/shortcut/command':
          response = await this.handleRoomShortcutCommand(request);
          break;
        case '/registry/agent-online':
          response = await this.handleRegistryAgentOnline(request, requestId);
          break;
        case '/registry/agent-offline':
          response = await this.handleRegistryAgentOffline(request);
          break;
        case '/registry/shortcut-grant-update':
          response = await this.handleRegistryShortcutGrantUpdate(request);
          break;
        case '/registry/devices':
          response = this.handleRegistryDevices(request);
          break;
        case '/registry/admin-reset-device':
          response = await this.handleRegistryAdminResetDevice(request);
          break;
        case '/registry/admin-enrollment-code':
          response = await this.handleRegistryAdminEnrollmentCode(request);
          break;
        case '/registry/status':
          response = this.handleRegistryStatus(request);
          break;
        case '/v1/shortcuts/command':
          response = await this.handleShortcutCommand(request);
          break;
        default:
          response = this.jsonResponse(
            {
              success: false,
              error: 'Not found',
              path: url.pathname,
            },
            { status: 404 }
          );
      }
      return enforcePublicServerErrorResponse(response, requestId);
    } catch (error) {
      this.logServerError('SessionManagerDO fetch error', requestId, url.pathname, error);
      return createPublicServerErrorResponse(requestId);
    }
  }

  private logServerError(
    message: string,
    requestId: string,
    operation: string,
    error: unknown
  ): void {
    const normalizedError = error instanceof Error ? error : new Error(String(error));
    const sanitizedError = sanitizeError(normalizedError);
    // L2: 保留 snake_case 字段名以兼容现有日志聚合与测试契约。
    this.logStructured('error', message, {
      request_id: requestId,
      error_type: sanitizedError.name,
      do_operation: operation,
      ...(operation === 'websocket_upgrade' ? { websocket_outcome: 'upgrade_failed' } : {}),
      error: {
        name: sanitizedError.name,
        message: sanitizedError.message,
        stack: sanitizedError.stack,
      },
    });
  }

  /**
   * L2: DO 内统一的结构化日志输出。
   *
   * DO 运行在独立 isolate，无法复用 Worker 侧的 Logger 实例，这里以
   * console 输出 JSON 结构化日志，便于外部聚合。仅透传调用方提供的
   * 字段（保持现有 snake_case 契约），error 字段会被 sanitizeError
   * 处理后再序列化。
   */
  private logStructured(
    level: 'error' | 'warn' | 'info',
    message: string,
    context: Record<string, unknown> = {}
  ): void {
    const payload: Record<string, unknown> = { level, message };
    for (const [key, value] of Object.entries(context)) {
      if (key === 'error' && value instanceof Error) {
        const sanitized = sanitizeError(value);
        payload.error = {
          name: sanitized.name,
          message: sanitized.message,
          stack: sanitized.stack,
        };
      } else {
        payload[key] = value;
      }
    }
    const text = JSON.stringify(payload);
    if (level === 'error') {
      console.error(text);
    } else if (level === 'warn') {
      console.warn(text);
    } else {
      console.info(text);
    }
  }
}
