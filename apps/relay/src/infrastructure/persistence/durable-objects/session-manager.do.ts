/**
 * Session Manager Durable Object
 * Manages WebSocket sessions using Cloudflare Durable Objects
 */

import {
  WSMessage,
  SessionInfo,
  Timer,
  RelayTransportMessage,
  RELAY_CLOSE_CODES,
} from '../../../types';
import { SESSION_CONSTANTS, SECURITY_CONSTANTS } from '../../../config/constants';
import {
  createPublicServerErrorResponse,
  enforcePublicServerErrorResponse,
  generateRequestId,
} from '../../../presentation/public-error-response';
import { sanitizeError } from '../../../utils/sensitive-error';

type PendingConnection = {
  timestamp: number;
  userAgent?: string;
  ip?: string;
};

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

type ShortcutGrantRecord = {
  grantId: string;
  deviceId: string;
  name: string;
  tokenHash: string;
  tokenPreview: string;
  allowedCommands: string[];
  expiresAt: number;
  revokedAt?: number;
  createdAt: number;
  updatedAt: number;
};

type PendingShortcutCommand = {
  resolve: (response: Response) => void;
  timer: Timer;
  clientRequestId: string;
  command: string;
};

export interface SessionManagerOptions {
  sessionTimeout?: number;
  cleanupInterval?: number;
  maxConcurrentSessions?: number;
  nonceCacheSize?: number;
  nonceRetentionSize?: number;
  agentAbsenceGraceMs?: number;
  shortcutCommandTimeoutMs?: number;
}

export class SessionManagerDO {
  private sessions: Map<string, WebSocket> = new Map();
  private sessionInfo: Map<string, SessionInfo> = new Map();
  private registryDevices: Map<string, DeviceRegistryRecord> = new Map();
  private relaySockets: Map<'agent', WebSocket> = new Map();
  private relayRoomInfo: RelayRoomInfo | null = null;
  private agentAbsenceTimer: Timer | null = null;
  private agentAbsentSince: number | null = null;
  private pendingShortcutCommands: Map<string, PendingShortcutCommand> = new Map();
  private usedRegistrationNonces: Map<string, number> = new Map();
  private nonces: Set<string> = new Set();
  private pendingConnections: Map<string, PendingConnection> = new Map();
  private options: Required<SessionManagerOptions>;
  private cleanupTimer: Timer | null = null;
  private readonly startTime = Date.now();

  constructor(
    private state: DurableObjectState,
    private env: any,
    options: SessionManagerOptions = {}
  ) {
    this.options = {
      sessionTimeout: options.sessionTimeout ?? SESSION_CONSTANTS.TIMEOUT,
      cleanupInterval: options.cleanupInterval ?? SESSION_CONSTANTS.CLEANUP_INTERVAL,
      maxConcurrentSessions:
        options.maxConcurrentSessions ?? SESSION_CONSTANTS.MAX_CONCURRENT_SESSIONS,
      nonceCacheSize: options.nonceCacheSize ?? SECURITY_CONSTANTS.NONCE.CACHE_SIZE,
      nonceRetentionSize: options.nonceRetentionSize ?? SECURITY_CONSTANTS.NONCE.RETENTION_SIZE,
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

      const noncesData = await this.state.storage.get<string[]>(
        SESSION_CONSTANTS.STORAGE_KEYS.NONCES
      );
      if (noncesData) {
        noncesData.forEach(nonce => this.nonces.add(nonce));
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

    } catch (error) {
      console.error('Failed to load session data:', error);
    }
  }

  /**
   * Save sessions to persistent storage
   */
  private async saveSessions(): Promise<void> {
    try {
      const sessions = Array.from(this.sessionInfo.values()).map(info =>
        this.normalizeSessionInfo(info.deviceId ?? this.state.id.toString(), info)
      );
      await this.state.storage.put(SESSION_CONSTANTS.STORAGE_KEYS.SESSIONS, sessions);
      await this.state.storage.put(SESSION_CONSTANTS.STORAGE_KEYS.NONCES, Array.from(this.nonces));
    } catch (error) {
      console.error('Failed to save session data:', error);
    }
  }

  private async saveRegistryDevices(): Promise<void> {
    await this.state.storage.put(
      SESSION_CONSTANTS.STORAGE_KEYS.DEVICE_REGISTRY,
      Array.from(this.registryDevices.values())
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

    (this.cleanupTimer as { unref?: () => void }).unref?.();
  }

  /**
   * Stop cleanup timer
   */
  private stopCleanupTimer(): void {
    if (this.cleanupTimer) {
      clearInterval(this.cleanupTimer);
      this.cleanupTimer = null;
    }
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
    (this.agentAbsenceTimer as { unref?: () => void }).unref?.();
  }

  /**
   * Add WebSocket session
   */
  async addSession(deviceId: string, ws: WebSocket): Promise<{ success: boolean; error?: string }> {
    // Check concurrent session limit
    if (this.sessions.size >= this.options.maxConcurrentSessions && !this.sessions.has(deviceId)) {
      return { success: false, error: 'Maximum concurrent sessions reached' };
    }

    // Cleanup old connection for this device
    const oldWs = this.sessions.get(deviceId);
    if (oldWs) {
      oldWs.close();
    }

    this.sessions.set(deviceId, ws);

    const now = Date.now();
    const existingInfo = this.sessionInfo.get(deviceId);
    const normalized = existingInfo
      ? this.normalizeSessionInfo(deviceId, existingInfo)
      : this.createSessionInfo(deviceId);

    const pending = this.pendingConnections.get(deviceId);
    const metadata = {
      ...(normalized.metadata ?? {}),
      ...(pending?.userAgent ? { userAgent: pending.userAgent } : {}),
      ...(pending?.ip ? { ipAddress: pending.ip } : {}),
    };

    this.sessionInfo.set(deviceId, {
      ...normalized,
      deviceId,
      isActive: true,
      connectedAt: normalized.connectedAt ?? now,
      createdAt: normalized.createdAt ?? now,
      lastActivity: now,
      lastPing: now,
      metadata: Object.keys(metadata).length > 0 ? metadata : normalized.metadata,
    });

    this.pendingConnections.delete(deviceId);

    await this.saveSessions();

    // Setup WebSocket event handlers
    ws.addEventListener('message', event => {
      this.handleIncomingMessage(deviceId, event);
    });

    ws.addEventListener('close', () => {
      if (this.sessions.get(deviceId) !== ws) {
        return;
      }

      this.sessions.delete(deviceId);
      const info = this.sessionInfo.get(deviceId);
      let updatedInfo = info;
      if (info) {
        const nowTimestamp = Date.now();
        updatedInfo = {
          ...info,
          isActive: false,
          lastActivity: nowTimestamp,
        };
        this.sessionInfo.set(deviceId, updatedInfo);
      }
      this.pendingConnections.delete(deviceId);
      void this.saveSessions();
    });

    ws.addEventListener('error', error => {
      console.error(`Device ${deviceId} WebSocket error:`, error);
    });

    return { success: true };
  }

  async addRelaySocket(
    sessionId: string,
    ws: WebSocket,
    metadata: {
      deviceId?: string;
      agentIdentityPublicKey?: string;
      registrationTimestamp?: number;
      registrationNonce?: string;
      registrationSignature?: string;
    } = {}
  ): Promise<{ success: boolean; error?: string }> {
    const now = Date.now();
    if (metadata.deviceId && metadata.agentIdentityPublicKey) {
      const registration = await this.syncRelayRegistryAgentOnline({
        deviceId: metadata.deviceId,
        sessionId,
        agentIdentityPublicKey: metadata.agentIdentityPublicKey,
        registrationTimestamp: metadata.registrationTimestamp,
        registrationNonce: metadata.registrationNonce,
        registrationSignature: metadata.registrationSignature,
        lastSeen: now,
      });
      if (!registration.ok) {
        return {
          success: false,
          error: registration.error ?? registration.code ?? 'Agent registration rejected',
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
        this.rejectPendingShortcutCommands('agent_unavailable', 'Agent disconnected.');
        this.scheduleAgentAbsenceTimeout(this.relayRoomInfo.deviceId, sessionId);
      }
    });

    ws.addEventListener('error', error => {
      console.error('Relay agent WebSocket error:', error);
    });

    return { success: true };
  }

  /**
   * Send message to device
   */
  async sendMessage(
    deviceId: string,
    message: WSMessage
  ): Promise<{ success: boolean; error?: string }> {
    const ws = this.sessions.get(deviceId);
    if (!ws) {
      return { success: false, error: 'Device not connected' };
    }

    try {
      ws.send(JSON.stringify(message));
      return { success: true };
    } catch (error) {
      console.error(`Failed to send message to device ${deviceId}:`, error);
      return { success: false, error: 'Failed to send message' };
    }
  }

  /**
   * Broadcast message to all devices
   */
  async broadcastMessage(
    message: WSMessage
  ): Promise<{ success: number; failed: number; errors: string[] }> {
    const results = { success: 0, failed: 0, errors: [] as string[] };

    for (const [deviceId, ws] of this.sessions) {
      try {
        ws.send(JSON.stringify(message));
        results.success++;
      } catch (error) {
        results.failed++;
        results.errors.push(
          `Device ${deviceId}: ${error instanceof Error ? error.message : 'Send failed'}`
        );
      }
    }

    return results;
  }

  /**
   * Check whether the local nonce cache has seen this value.
   * Command auth does not currently call this cache.
   */
  isNonceUsed(nonce: string): boolean {
    return this.nonces.has(nonce);
  }

  /**
   * Mark nonce as used
   */
  async markNonceUsed(nonce: string): Promise<void> {
    this.nonces.add(nonce);

    // Manage nonce cache
    if (this.nonces.size > this.options.nonceCacheSize) {
      const nonceArray = Array.from(this.nonces);
      const toKeep = nonceArray.slice(-this.options.nonceRetentionSize);
      this.nonces = new Set(toKeep);
    }

    await this.saveSessions();
  }

  /**
   * Get connected devices
   */
  getConnectedDevices(): string[] {
    return Array.from(this.sessions.keys());
  }

  /**
   * Get session info
   */
  getSessionInfo(deviceId: string): SessionInfo | undefined {
    return this.sessionInfo.get(deviceId);
  }

  /**
   * Get all session info
   */
  getAllSessionInfo(): SessionInfo[] {
    return Array.from(this.sessionInfo.values());
  }

  /**
   * Update last ping time
   */
  async updateLastPing(deviceId: string): Promise<void> {
    const info = this.sessionInfo.get(deviceId);
    if (info) {
      const now = Date.now();
      info.lastPing = now;
      info.lastActivity = now;
      this.sessionInfo.set(deviceId, info);
      await this.saveSessions();
    }
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
        const ws = this.sessions.get(deviceId);
        if (ws) {
          ws.close();
        }
        this.sessions.delete(deviceId);
        this.sessionInfo.delete(deviceId);
        cleanedCount++;
      }
    }

    await this.saveSessions();
    return {
      cleaned: cleanedCount,
      remaining: this.sessions.size,
    };
  }

  /**
   * Disconnect device
   */
  async disconnectDevice(deviceId: string): Promise<boolean> {
    const ws = this.sessions.get(deviceId);
    if (ws) {
      ws.close();
      this.sessions.delete(deviceId);
      this.sessionInfo.delete(deviceId);
      await this.saveSessions();
      return true;
    }
    return false;
  }

  /**
   * Disconnect all devices
   */
  async disconnectAllDevices(): Promise<number> {
    const count = this.sessions.size;
    for (const [_, ws] of this.sessions) {
      ws.close();
    }
    this.sessions.clear();
    this.sessionInfo.clear();
    await this.saveSessions();
    return count;
  }

  /**
   * Get session statistics
   */
  getSessionStats() {
    const now = Date.now();
    const sessions = Array.from(this.sessionInfo.values());
    const activeSessions = sessions.filter(
      info =>
        now - (info.lastPing ?? info.lastActivity ?? info.connectedAt ?? now) <=
        this.options.sessionTimeout
    );

    const averageDuration =
      sessions.length > 0
        ? sessions.reduce((sum, info) => {
            const connectedAt = info.connectedAt ?? info.createdAt ?? now;
            return sum + (now - connectedAt);
          }, 0) / sessions.length
        : 0;

    return {
      totalSessions: sessions.length,
      activeSessions: activeSessions.length,
      noncesCached: this.nonces.size,
      uptime: now - this.startTime,
      averageSessionDuration: averageDuration,
    };
  }

  private createSessionInfo(deviceId: string): SessionInfo {
    const now = Date.now();
    return {
      sessionId: `${deviceId}-${now}`,
      deviceId,
      isActive: true,
      createdAt: now,
      lastActivity: now,
      connectedAt: now,
      lastPing: now,
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

    const ok = data?.ok !== false;
    const body = {
      ok,
      request_id: pending.clientRequestId,
      command: typeof data?.command === 'string' ? data.command : pending.command,
      success: data?.success === true,
      message: typeof data?.message === 'string' ? data.message : undefined,
      data: typeof data?.resultData === 'object' ? data.resultData : data?.data,
      code: typeof data?.code === 'string' ? data.code : undefined,
      error: typeof data?.error === 'string' ? data.error : undefined,
      timestamp: Date.now(),
    };
    const status = ok ? 200 : this.shortcutFailureStatus(body.code);
    pending.resolve(this.jsonResponse(body, { status }));
  }

  private rejectPendingShortcutCommands(code: string, error: string): void {
    for (const pending of this.pendingShortcutCommands.values()) {
      clearTimeout(pending.timer);
      pending.resolve(
        this.shortcutError(
          code,
          error,
          this.shortcutFailureStatus(code),
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
        new Request('http://registry/registry/agent-online', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        })
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
        new Request('http://registry/registry/shortcut-grant-update', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload),
        })
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
      new Request('http://registry/registry/agent-offline', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ deviceId, sessionId }),
      })
    );
  }

  private handleIncomingMessage(deviceId: string, event: MessageEvent): void {
    const info = this.sessionInfo.get(deviceId);
    if (!info) {
      return;
    }

    const now = Date.now();
    let lastPing = info.lastPing ?? now;
    let shouldReplyPong = false;
    let replyId: string | undefined;
    let receivedTimestamp: number | undefined;

    if (typeof event.data === 'string') {
      try {
        const payload = JSON.parse(event.data) as Partial<WSMessage> & {
          id?: string;
          timestamp?: number;
          ts?: number;
        };
        if (payload.type === 'pong' || payload.type === 'ping') {
          lastPing = now;
        }
        if (payload.type === 'ping') {
          shouldReplyPong = true;
          replyId = payload.id;
          receivedTimestamp = payload.timestamp ?? payload.ts;
        }
      } catch {
        lastPing = now;
      }
    } else {
      lastPing = now;
    }

    const updatedInfo = {
      ...info,
      lastActivity: now,
      lastPing,
    };

    this.sessionInfo.set(deviceId, updatedInfo);

    this.state.waitUntil(this.saveSessions());

    if (shouldReplyPong) {
      const ws = this.sessions.get(deviceId);
      if (!ws) {
        return;
      }

      const pong: WSMessage = {
        type: 'pong',
        id: replyId,
        timestamp: now,
        data: {
          deviceId,
          receivedTimestamp,
        },
      };
      ws.send(JSON.stringify(pong));
    }
  }

  private jsonResponse<T>(body: T, init?: ResponseInit): Response {
    return Response.json(body, init);
  }

  private shortcutFailureStatus(code?: string): number {
    switch (code) {
      case 'grant_expired':
      case 'grant_revoked':
      case 'command_not_allowed':
        return 403;
      case 'agent_unavailable':
        return 503;
      case 'command_timeout':
        return 504;
      default:
        return 400;
    }
  }

  private methodNotAllowed(allowed: string[]): Response {
    return this.jsonResponse(
      {
        success: false,
        error: 'Method not allowed',
      },
      {
        status: 405,
        headers: {
          Allow: allowed.join(', '),
        },
      }
    );
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
      return this.methodNotAllowed(['POST']);
    }

    const payload = await this.readJsonObject(request);
    if (!payload) {
      return this.shortcutError(
        'invalid_shortcut_command',
        'Shortcut command dispatch body must be a valid JSON object.',
        400
      );
    }
    const clientRequestId = typeof payload.requestId === 'string' ? payload.requestId : '';
    const targetDeviceId = typeof payload.deviceId === 'string' ? payload.deviceId : '';
    const command = typeof payload.command === 'string' ? payload.command : '';
    const grantId = typeof payload.grantId === 'string' ? payload.grantId : '';
    if (!clientRequestId || !command || !grantId) {
      return this.shortcutError(
        'invalid_shortcut_command',
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
        'agent_unavailable',
        'Shortcut command target does not match this agent room.',
        503,
        clientRequestId,
        command
      );
    }

    const agent = this.relaySockets.get('agent');
    if (!agent) {
      return this.shortcutError(
        'agent_unavailable',
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
            'command_timeout',
            'Agent did not return a shortcut result before timeout.',
            504,
            clientRequestId,
            command
          )
        );
      }, this.options.shortcutCommandTimeoutMs);
      (timer as { unref?: () => void }).unref?.();
      this.pendingShortcutCommands.set(dispatchId, {
        resolve,
        timer,
        clientRequestId,
        command,
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
            },
          })
        );
      } catch {
        clearTimeout(timer);
        this.pendingShortcutCommands.delete(dispatchId);
        resolve(
          this.shortcutError(
            'agent_unavailable',
            'Failed to send shortcut command to agent.',
            503,
            clientRequestId,
            command
          )
        );
      }
    });
  }

  private async handleRegistryAgentOnline(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return this.methodNotAllowed(['POST']);
    }

    const payload = (await request.json()) as {
      deviceId?: string;
      sessionId?: string;
      agentIdentityPublicKey?: string;
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
      return this.jsonResponse(
        {
          ok: false,
          error: 'Agent identity key does not match first-seen binding.',
          code: 'agent_identity_mismatch',
        },
        { status: 403 }
      );
    }

    const now = Date.now();
    if (existing?.agentIdentityPublicKey) {
      if (
        !payload.registrationTimestamp ||
        !payload.registrationNonce ||
        !payload.registrationSignature
      ) {
        return this.jsonResponse(
          {
            ok: false,
            error: 'Agent registration signature is required after first-seen binding.',
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
        return this.jsonResponse(
          {
            ok: false,
            error: 'Agent registration request was already used.',
            code: 'agent_registration_replayed',
          },
          { status: 409 }
        );
      }
      const transcript = this.buildAgentRegistrationTranscript({
        deviceId: payload.deviceId,
        sessionId: payload.sessionId,
        agentIdentityPublicKey: payload.agentIdentityPublicKey,
        timestamp: Number(payload.registrationTimestamp),
        nonce: payload.registrationNonce,
      });
      const signatureValid = await this.verifyEd25519Signature(
        existing.agentIdentityPublicKey,
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
      this.usedRegistrationNonces.set(nonceKey, now + SESSION_CONSTANTS.AGENT_REGISTRATION_SKEW);
    }

    const record: DeviceRegistryRecord = {
      ...(existing ?? {
        deviceId: payload.deviceId,
        lastSeen: payload.lastSeen ?? now,
        connected: false,
      }),
      deviceId: payload.deviceId,
      connected: true,
      liveSessionId: payload.sessionId,
      sessionId: payload.sessionId,
      agentIdentityPublicKey: payload.agentIdentityPublicKey,
      connectedAt: existing?.connectedAt ?? now,
      lastPing: now,
      lastSeen: payload.lastSeen ?? now,
    };

    this.registryDevices.set(payload.deviceId, record);
    await this.saveRegistryDevices();

    return this.jsonResponse({
      ok: true,
      success: true,
      device: record,
    });
  }

  private async handleRegistryAgentOffline(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return this.methodNotAllowed(['POST']);
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
      return this.methodNotAllowed(['POST']);
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

    const grant = this.normalizeShortcutGrant(payload.deviceId, payload.grant);
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
      return this.methodNotAllowed(['POST']);
    }

    const token = this.extractShortcutToken(request);
    if (!token) {
      return this.shortcutError('invalid_token', 'Shortcut token is missing or malformed.', 401);
    }

    const payload = await this.readJsonObject(request);
    if (!payload) {
      return this.shortcutError(
        'invalid_shortcut_command',
        'Shortcut command body must be a valid JSON object.',
        400
      );
    }
    const deviceId = typeof payload.device_id === 'string' ? payload.device_id.trim() : '';
    const command = typeof payload.command === 'string' ? payload.command.trim() : '';
    const requestId =
      typeof payload.request_id === 'string' && payload.request_id.trim()
        ? payload.request_id.trim()
        : `shortcut-${this.createRandomToken(12)}`;

    if (!deviceId || !command) {
      return this.shortcutError(
        'invalid_shortcut_command',
        'Shortcut command requires device_id and command.',
        400,
        requestId,
        command
      );
    }

    const tokenHash = await this.hashShortcutToken(token);
    const record = this.registryDevices.get(deviceId);
    const grant = record?.shortcutGrants?.find(candidate => candidate.tokenHash === tokenHash);
    if (!record || !grant) {
      return this.shortcutError('invalid_token', 'Shortcut token is invalid.', 401, requestId, command);
    }
    if (grant.revokedAt) {
      return this.shortcutError('grant_revoked', 'Shortcut grant has been revoked.', 403, requestId, command);
    }
    if (Date.now() >= grant.expiresAt) {
      return this.shortcutError('grant_expired', 'Shortcut grant has expired.', 403, requestId, command);
    }
    if (!grant.allowedCommands.includes(command)) {
      return this.shortcutError(
        'command_not_allowed',
        'Shortcut grant does not allow this command.',
        403,
        requestId,
        command
      );
    }
    if (!record.connected || !record.liveSessionId) {
      return this.shortcutError('agent_unavailable', 'Agent is not online.', 503, requestId, command);
    }
    if (
      typeof this.env?.CICADA_SESSIONS?.idFromName !== 'function' ||
      typeof this.env?.CICADA_SESSIONS?.get !== 'function'
    ) {
      return this.shortcutError('agent_unavailable', 'Agent routing is unavailable.', 503, requestId, command);
    }

    const sessionRoom = this.env.CICADA_SESSIONS.get(
      this.env.CICADA_SESSIONS.idFromName(record.liveSessionId)
    );
    const response = await sessionRoom.fetch(
      new Request('http://session/shortcut/command', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          requestId,
          deviceId,
          grantId: grant.grantId,
          command,
        }),
      })
    );
    return new Response(response.body as any, {
      status: response.status,
      headers: response.headers as any,
    });
  }

  private normalizeShortcutGrant(
    deviceId: string,
    value?: Partial<ShortcutGrantRecord>
  ): ShortcutGrantRecord | undefined {
    if (!value || typeof value !== 'object') {
      return undefined;
    }
    const grantId = typeof value.grantId === 'string' ? value.grantId.trim() : '';
    const name = typeof value.name === 'string' ? value.name.trim() : '';
    const tokenHash = typeof value.tokenHash === 'string' ? value.tokenHash.trim() : '';
    const tokenPreview = typeof value.tokenPreview === 'string' ? value.tokenPreview.trim() : '';
    const allowedCommands = this.normalizeShortcutCommands(value.allowedCommands);
    const expiresAt = typeof value.expiresAt === 'number' ? value.expiresAt : 0;
    const createdAt = typeof value.createdAt === 'number' ? value.createdAt : Date.now();
    const updatedAt = typeof value.updatedAt === 'number' ? value.updatedAt : Date.now();
    if (!grantId || !name || !tokenHash || !tokenPreview || allowedCommands.length === 0 || expiresAt <= Date.now()) {
      return undefined;
    }
    return {
      grantId,
      deviceId,
      name,
      tokenHash,
      tokenPreview,
      allowedCommands,
      expiresAt,
      revokedAt: typeof value.revokedAt === 'number' ? value.revokedAt : undefined,
      createdAt,
      updatedAt,
    };
  }

  private normalizeShortcutCommands(value?: string[]): string[] {
    if (!Array.isArray(value)) {
      return [];
    }
    return Array.from(
      new Set(
        value
          .filter(command => typeof command === 'string')
          .map(command => command.trim())
          .filter(Boolean)
      )
    );
  }

  private extractShortcutToken(request: Request): string | undefined {
    const auth = request.headers.get('Authorization') ?? request.headers.get('authorization') ?? '';
    const match = auth.match(/^Bearer\s+(cicada_sc_[A-Za-z0-9_-]+)$/);
    return match?.[1];
  }

  private async hashShortcutToken(token: string): Promise<string> {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
    return this.base64UrlEncode(new Uint8Array(digest));
  }

  private shortcutError(
    code: string,
    error: string,
    status: number,
    requestId = '',
    command = ''
  ): Response {
    return this.jsonResponse(
      {
        ok: false,
        request_id: requestId,
        command,
        code,
        error,
        timestamp: Date.now(),
      },
      { status }
    );
  }

  private pruneUsedRegistrationNonces(now: number): void {
    for (const [nonce, expiresAt] of this.usedRegistrationNonces.entries()) {
      if (now >= expiresAt) {
        this.usedRegistrationNonces.delete(nonce);
      }
    }
  }

  private async readJsonObject(request: Request): Promise<Record<string, unknown> | undefined> {
    try {
      const payload = await request.json();
      if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
        return undefined;
      }
      return payload as Record<string, unknown>;
    } catch {
      return undefined;
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
  }): Uint8Array {
    return this.buildLengthPrefixedTranscript([
      'cicada-agent-registration-v1',
      payload.deviceId,
      payload.sessionId,
      payload.agentIdentityPublicKey,
      String(payload.timestamp),
      payload.nonce,
    ]);
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

  private handleRegistryDevices(request: Request): Response {
    if (request.method !== 'GET') {
      return this.methodNotAllowed(['GET']);
    }

    const now = Date.now();
    const devices = Array.from(this.registryDevices.values())
      .sort((left, right) => right.lastSeen - left.lastSeen)
      .map(device => ({
        deviceId: device.deviceId,
        connected: device.connected,
        connectedAt: device.connectedAt,
        lastPing: device.lastPing ?? device.lastSeen,
        uptime: device.connected && device.connectedAt ? now - device.connectedAt : undefined,
        ipAddress: device.ipAddress,
        userAgent: device.userAgent,
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
      return this.methodNotAllowed(['GET']);
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
          },
          { status: 429 }
        );
      }

      // Return the client WebSocket to the original requester
      return this.createWebSocketResponse(client);
    } catch (error) {
      this.logServerError('WebSocket upgrade failed', requestId, error);
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
          response = await this.handleRegistryAgentOnline(request);
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
      this.logServerError('SessionManagerDO fetch error', requestId, error);
      return createPublicServerErrorResponse(requestId);
    }
  }

  private logServerError(message: string, requestId: string, error: unknown): void {
    const normalizedError = error instanceof Error ? error : new Error(String(error));
    const sanitizedError = sanitizeError(normalizedError);
    console.error(
      JSON.stringify({
        level: 'error',
        message,
        request_id: requestId,
        error: {
          name: sanitizedError.name,
          message: sanitizedError.message,
          stack: sanitizedError.stack,
        },
      })
    );
  }

  /**
   * Update options
   */
  updateOptions(newOptions: Partial<SessionManagerOptions>): void {
    this.options = { ...this.options, ...newOptions };

    if (newOptions.cleanupInterval) {
      this.startCleanupTimer();
    }
  }

  /**
   * Destroy session manager
   */
  async destroy(): Promise<void> {
    this.stopCleanupTimer();
    await this.disconnectAllDevices();
  }
}
