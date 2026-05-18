/**
 * Session Manager Durable Object
 * Manages WebSocket sessions using Cloudflare Durable Objects
 */

import { WSMessage, SessionInfo, Timer } from '../../../types';
import { SESSION_CONSTANTS, SECURITY_CONSTANTS } from '../../../config/constants';

type PendingConnection = {
  timestamp: number;
  userAgent?: string;
  ip?: string;
};

export interface SessionManagerOptions {
  sessionTimeout?: number;
  cleanupInterval?: number;
  maxConcurrentSessions?: number;
  nonceCacheSize?: number;
  nonceRetentionSize?: number;
}

export class SessionManagerDO {
  private sessions: Map<string, WebSocket> = new Map();
  private sessionInfo: Map<string, SessionInfo> = new Map();
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

    console.log(
      `Device ${deviceId} connected, current: ${this.sessions.size}/${this.options.maxConcurrentSessions}`
    );

    // Setup WebSocket event handlers
    ws.addEventListener('message', event => {
      this.handleIncomingMessage(deviceId, event);
    });

    ws.addEventListener('close', () => {
      this.sessions.delete(deviceId);
      const info = this.sessionInfo.get(deviceId);
      if (info) {
        const nowTimestamp = Date.now();
        this.sessionInfo.set(deviceId, {
          ...info,
          isActive: false,
          lastActivity: nowTimestamp,
        });
      }
      this.pendingConnections.delete(deviceId);
      void this.saveSessions();
      console.log(`Device ${deviceId} disconnected`);
    });

    ws.addEventListener('error', error => {
      console.error(`Device ${deviceId} WebSocket error:`, error);
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
   * Check if nonce is used (prevent replay attacks)
   */
  isNonceUsed(nonce: string): boolean {
    return this.nonces.has(nonce);
  }

  /**
   * Mark nonce as used
   */
  async markNonceUsed(nonce: string): Promise<void> {
    this.nonces.add(nonce);
    await this.saveSessions();

    // Manage nonce cache
    if (this.nonces.size > this.options.nonceCacheSize) {
      const nonceArray = Array.from(this.nonces);
      const toKeep = nonceArray.slice(-this.options.nonceRetentionSize);
      this.nonces = new Set(toKeep);
      await this.saveSessions();
    }
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
        console.log(`Cleanup inactive device: ${deviceId}`);
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
      console.log(`Force disconnect device: ${deviceId}`);
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
    console.log(`Force disconnect all devices, total: ${count}`);
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

  private handleIncomingMessage(deviceId: string, event: MessageEvent): void {
    const info = this.sessionInfo.get(deviceId);
    if (!info) {
      return;
    }

    const now = Date.now();
    let lastPing = info.lastPing ?? now;

    if (typeof event.data === 'string') {
      try {
        const payload = JSON.parse(event.data) as WSMessage;
        if (payload.type === 'pong' || payload.type === 'ping') {
          lastPing = now;
        }
      } catch {
        lastPing = now;
      }
    } else {
      lastPing = now;
    }

    this.sessionInfo.set(deviceId, {
      ...info,
      lastActivity: now,
      lastPing,
    });

    this.state.waitUntil(this.saveSessions());
  }

  private jsonResponse<T>(body: T, init?: ResponseInit): Response {
    return Response.json(body, init);
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

  private async handleConnect(request: Request, deviceId: string): Promise<Response> {
    if (request.method !== 'POST') {
      return this.methodNotAllowed(['POST']);
    }

    try {
      const payload = (await request.json()) as {
        deviceId?: string;
        timestamp?: number;
        userAgent?: string;
        ipAddress?: string;
      };

      const resolvedDeviceId = payload.deviceId ?? deviceId;
      if (!resolvedDeviceId) {
        return this.jsonResponse(
          {
            success: false,
            error: 'Missing device identifier',
          },
          { status: 400 }
        );
      }

      if (
        this.sessions.size >= this.options.maxConcurrentSessions &&
        !this.sessions.has(resolvedDeviceId)
      ) {
        return this.jsonResponse(
          {
            success: false,
            error: 'Maximum concurrent sessions reached',
          },
          { status: 429 }
        );
      }

      const now = Date.now();
      const ipFromHeaders = request.headers.get('CF-Connecting-IP') ?? undefined;
      const userAgentFromHeaders = request.headers.get('User-Agent') ?? undefined;

      const existing = this.sessionInfo.get(resolvedDeviceId);
      const normalized = existing
        ? this.normalizeSessionInfo(resolvedDeviceId, existing)
        : this.createSessionInfo(resolvedDeviceId);

      const metadata = {
        ...(normalized.metadata ?? {}),
        ...(payload.ipAddress ? { ipAddress: payload.ipAddress } : {}),
        ...(ipFromHeaders ? { ipAddress: ipFromHeaders } : {}),
        ...(payload.userAgent ? { userAgent: payload.userAgent } : {}),
        ...(userAgentFromHeaders ? { userAgent: userAgentFromHeaders } : {}),
      };

      this.sessionInfo.set(resolvedDeviceId, {
        ...normalized,
        deviceId: resolvedDeviceId,
        isActive: normalized.isActive ?? false,
        lastActivity: now,
        lastPing: normalized.lastPing ?? now,
        metadata: Object.keys(metadata).length > 0 ? metadata : normalized.metadata,
      });

      this.pendingConnections.set(resolvedDeviceId, {
        timestamp: payload.timestamp ?? now,
        userAgent: payload.userAgent ?? userAgentFromHeaders,
        ip: payload.ipAddress ?? ipFromHeaders,
      });

      await this.saveSessions();

      return this.jsonResponse({ success: true });
    } catch (error) {
      console.error('Failed to process connect request:', error);
      return this.jsonResponse(
        {
          success: false,
          error: 'Invalid connect payload',
        },
        { status: 400 }
      );
    }
  }

  private async handleSend(request: Request, deviceId: string): Promise<Response> {
    if (request.method !== 'POST') {
      return this.methodNotAllowed(['POST']);
    }

    try {
      const targetDeviceId = request.headers.get('X-Device-ID') ?? deviceId;
      if (!targetDeviceId) {
        return this.jsonResponse(
          {
            success: false,
            error: 'Missing device identifier',
          },
          { status: 400 }
        );
      }

      const message = (await request.json()) as WSMessage;
      const result = await this.sendMessage(targetDeviceId, message);

      if (!result.success) {
        return this.jsonResponse(
          {
            success: false,
            error: result.error,
          },
          { status: 400 }
        );
      }

      return this.jsonResponse({
        success: true,
        commandId: (message as unknown as Record<string, unknown>).id as string | undefined,
        timestamp: Date.now(),
      });
    } catch (error) {
      console.error('Failed to send message:', error);
      return this.jsonResponse(
        {
          success: false,
          error: 'Failed to send message',
        },
        { status: 500 }
      );
    }
  }

  private async handleStatus(request: Request, deviceId: string): Promise<Response> {
    if (request.method !== 'GET') {
      return this.methodNotAllowed(['GET']);
    }

    const resolvedDeviceId = request.headers.get('X-Device-ID') ?? deviceId;
    if (!resolvedDeviceId) {
      return this.jsonResponse(
        {
          success: false,
          error: 'Missing device identifier',
        },
        { status: 400 }
      );
    }

    const info = this.sessionInfo.get(resolvedDeviceId);
    const connected = this.sessions.has(resolvedDeviceId);
    const now = Date.now();

    return this.jsonResponse({
      deviceId: resolvedDeviceId,
      connected,
      sessionInfo: info ?? null,
      lastActivity: info?.lastActivity ?? null,
      lastPing: info?.lastPing ?? null,
      connectedAt: info?.connectedAt ?? null,
      uptime: info?.connectedAt ? now - info.connectedAt : null,
    });
  }

  private async handleInfo(request: Request, deviceId: string): Promise<Response> {
    if (request.method !== 'GET') {
      return this.methodNotAllowed(['GET']);
    }

    const resolvedDeviceId = request.headers.get('X-Device-ID') ?? deviceId;
    const info = this.sessionInfo.get(resolvedDeviceId);
    const connected = this.sessions.has(resolvedDeviceId);

    return this.jsonResponse({
      success: true,
      deviceId: resolvedDeviceId,
      connected,
      sessionInfo: info ?? null,
    });
  }

  private async handleDisconnect(request: Request, deviceId: string): Promise<Response> {
    if (request.method !== 'POST') {
      return this.methodNotAllowed(['POST']);
    }

    try {
      const payload = (await request.json()) as { device_id?: string };
      const resolvedDeviceId = payload.device_id ?? deviceId;

      if (!resolvedDeviceId) {
        return this.jsonResponse(
          {
            success: false,
            error: 'Missing device identifier',
          },
          { status: 400 }
        );
      }

      const disconnected = await this.disconnectDevice(resolvedDeviceId);
      return this.jsonResponse({
        success: disconnected,
        error: disconnected ? undefined : 'Device not found or already disconnected',
      });
    } catch (error) {
      console.error('Failed to disconnect:', error);
      return this.jsonResponse(
        {
          success: false,
          error: 'Failed to disconnect',
        },
        { status: 500 }
      );
    }
  }

  private async handleStats(_request: Request): Promise<Response> {
    const stats = this.getSessionStats();
    return this.jsonResponse({
      success: true,
      stats,
    });
  }

  private handleDevices(request: Request): Response {
    if (request.method !== 'GET') {
      return this.methodNotAllowed(['GET']);
    }

    return this.jsonResponse({
      success: true,
      devices: this.getConnectedDevices(),
      sessions: this.getAllSessionInfo(),
    });
  }

  private async handleCleanup(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return this.methodNotAllowed(['POST']);
    }

    const result = await this.cleanupInactiveSessions();
    return this.jsonResponse({
      success: true,
      ...result,
    });
  }

  private async handleWebSocket(request: Request, deviceId: string): Promise<Response> {
    console.log('[DO] handleWebSocket called for device:', deviceId);
    console.log('[DO] Request headers:', Object.fromEntries(request.headers.entries()));

    // Try multiple ways to extract WebSocket
    let webSocket = (request as any).webSocket;
    console.log('[DO] WebSocket via .webSocket:', !!webSocket);

    if (!webSocket) {
      // Check if it's in the request object with different casing
      webSocket = (request as any).websocket || (request as any).WebSocket;
      console.log('[DO] WebSocket via alt properties:', !!webSocket);
    }

    if (!webSocket) {
      console.log('[DO ERROR] No WebSocket in request');
      console.log('[DO] Request keys:', Object.keys(request as any));
      return this.jsonResponse(
        {
          success: false,
          error: 'Expected WebSocket request',
        },
        { status: 400 }
      );
    }

    const resolvedDeviceId = deviceId;

    try {
      console.log('[DO] Accepting WebSocket');
      webSocket.accept();
      console.log('[DO] WebSocket accepted');

      console.log('[DO] Adding session');
      const result = await this.addSession(resolvedDeviceId, webSocket);
      console.log('[DO] Session add result:', result);
      if (!result.success) {
        webSocket.close(1013, result.error ?? 'Session limit reached');
        return this.jsonResponse(
          {
            success: false,
            error: result.error ?? 'Failed to register session',
          },
          { status: 429 }
        );
      }

      const ip = request.headers.get('CF-Connecting-IP') ?? undefined;
      const userAgent = request.headers.get('User-Agent') ?? undefined;
      const metadataUpdates = {
        ...(ip ? { ipAddress: ip } : {}),
        ...(userAgent ? { userAgent } : {}),
      };

      if (Object.keys(metadataUpdates).length > 0) {
        const info = this.sessionInfo.get(resolvedDeviceId);
        if (info) {
          this.sessionInfo.set(resolvedDeviceId, {
            ...info,
            metadata: {
              ...(info.metadata ?? {}),
              ...metadataUpdates,
            },
          });
          this.state.waitUntil(this.saveSessions());
        }
      }

      console.log('[DO] Returning WebSocket response');
      return this.createWebSocketResponse(webSocket);
    } catch (error) {
      console.error('[DO ERROR] Failed to establish WebSocket session:', error);
      try {
        webSocket.close(1011, 'Internal error');
      } catch {
        // ignore
      }
      return this.jsonResponse(
        {
          success: false,
          error: 'WebSocket setup failed',
        },
        { status: 500 }
      );
    }
  }

  private handleOptions(): Response {
    return new Response(null, { status: 204 });
  }

  private async handleWebSocketUpgrade(request: Request, deviceId: string): Promise<Response> {
    console.log('[DO] handleWebSocketUpgrade called for device:', deviceId);

    try {
      // Create WebSocketPair in Durable Object
      // eslint-disable-next-line no-undef
      const pair = new WebSocketPair();
      const [client, server] = [pair[0], pair[1]];

      console.log('[DO] WebSocketPair created');

      // Accept the WebSocket connection
      server.accept();
      console.log('[DO] WebSocket accepted');

      // Add session
      const result = await this.addSession(deviceId, server);
      console.log('[DO] addSession result:', result);

      if (!result.success) {
        server.close(1013, result.error ?? 'Session limit reached');
        return this.jsonResponse(
          {
            success: false,
            error: result.error ?? 'Failed to add session',
          },
          { status: 429 }
        );
      }

      // Return the client WebSocket to the original requester
      console.log('[DO] Returning WebSocket upgrade response');
      return this.createWebSocketResponse(client);
    } catch (error) {
      console.error('[DO ERROR] WebSocket upgrade failed:', error);
      return this.jsonResponse(
        {
          success: false,
          error: 'WebSocket upgrade failed',
          details: error instanceof Error ? error.message : String(error),
        },
        { status: 500 }
      );
    }
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const deviceId = this.getDeviceId(request.headers.get('X-Device-ID'));

    console.log('[DO] fetch called:', {
      method: request.method,
      pathname: url.pathname,
      upgrade: request.headers.get('Upgrade'),
      deviceId,
    });

    if (request.method === 'OPTIONS') {
      return this.handleOptions();
    }

    // Check if this is a WebSocket upgrade request
    const upgrade = request.headers.get('Upgrade');
    console.log('[DO] Upgrade header value:', upgrade);
    if (upgrade && upgrade.toLowerCase().includes('websocket')) {
      console.log('[DO] WebSocket upgrade detected');
      return await this.handleWebSocketUpgrade(request, deviceId);
    }

    try {
      switch (url.pathname) {
        case '/connect':
          return await this.handleConnect(request, deviceId);
        case '/send':
          return await this.handleSend(request, deviceId);
        case '/status':
          return await this.handleStatus(request, deviceId);
        case '/info':
          return await this.handleInfo(request, deviceId);
        case '/disconnect':
          return await this.handleDisconnect(request, deviceId);
        case '/stats':
          return await this.handleStats(request);
        case '/devices':
          return this.handleDevices(request);
        case '/cleanup':
          return await this.handleCleanup(request);
        case '/websocket':
          return await this.handleWebSocket(request, deviceId);
        default:
          return this.jsonResponse(
            {
              success: false,
              error: 'Not found',
              path: url.pathname,
            },
            { status: 404 }
          );
      }
    } catch (error) {
      console.error('SessionManagerDO fetch error:', error);
      return this.jsonResponse(
        {
          success: false,
          error: 'Internal server error',
        },
        { status: 500 }
      );
    }
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
