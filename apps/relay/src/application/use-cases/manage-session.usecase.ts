import type { Result } from '@cicada/shared/errors/result';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { DeviceId, SessionId } from '@cicada/shared/types/common.types';
import type { SessionService } from '../services/session.service';
import type { DeviceService } from '../services/device.service';

export interface CreateSessionRequest {
  deviceId: DeviceId;
  platform: string;
  version: string;
  metadata?: Record<string, unknown>;
}

export interface CreateSessionResponse {
  sessionId: string;
  deviceId: string;
  connectedAt: number;
}

export interface CloseSessionRequest {
  sessionId: SessionId;
}

export interface ManageSessionUseCaseDeps {
  sessionService: SessionService;
  deviceService: DeviceService;
}

export class ManageSessionUseCase {
  constructor(private readonly deps: ManageSessionUseCaseDeps) {}

  async createSession(
    request: CreateSessionRequest
  ): Promise<Result<CreateSessionResponse, CicadaError>> {
    // 1. Register or update device
    const deviceResult = await this.deps.deviceService.registerDevice(
      request.deviceId,
      request.platform,
      request.version,
      request.metadata as any // TODO: Fix type mismatch
    );

    if (!deviceResult.success) {
      return { success: false, error: deviceResult.error };
    }

    // 2. Create session
    const sessionResult = await this.deps.sessionService.createSession(
      request.deviceId,
      request.metadata
    );

    if (!sessionResult.success) {
      return { success: false, error: sessionResult.error };
    }

    const session = sessionResult.data;

    // 3. Mark device as connected
    const sessionIdStr = session.id?.toString() ?? '';
    const connectResult = await this.deps.deviceService.connectDevice(
      request.deviceId,
      sessionIdStr
    );

    if (!connectResult.success) {
      // Rollback session creation
      if (session.id) {
        await this.deps.sessionService.closeSession(session.id);
      }
      return { success: false, error: connectResult.error };
    }

    // 4. Return response
    return {
      success: true,
      data: {
        sessionId: session.id?.toString() ?? '',
        deviceId: request.deviceId,
        connectedAt: session.connectedAt,
      },
    };
  }

  async closeSession(request: CloseSessionRequest): Promise<Result<void, CicadaError>> {
    // 1. Get session to find device
    const sessionResult = await this.deps.sessionService.getSession(request.sessionId);
    if (!sessionResult.success) {
      return { success: false, error: sessionResult.error };
    }

    const session = sessionResult.data;
    if (!session) {
      return {
        success: false,
        error: new CicadaError(
          `Session ${request.sessionId} not found`,
          ErrorCode.SESSION_NOT_FOUND,
          { severity: ErrorSeverity.MEDIUM }
        ),
      };
    }

    // 2. Close session
    const closeResult = await this.deps.sessionService.closeSession(request.sessionId);
    if (!closeResult.success) {
      return closeResult;
    }

    // 3. Mark device as disconnected
    await this.deps.deviceService.disconnectDevice(session.deviceId);

    return { success: true, data: undefined };
  }

  async updateActivity(sessionId: SessionId): Promise<Result<void, CicadaError>> {
    const updateResult = await this.deps.sessionService.updateActivity(sessionId);
    if (!updateResult.success) {
      return { success: false, error: updateResult.error };
    }

    return { success: true, data: undefined };
  }

  async recordMessage(sessionId: SessionId): Promise<Result<void, CicadaError>> {
    return this.deps.sessionService.recordMessage(sessionId);
  }

  async cleanupExpiredSessions(timeoutMs: number): Promise<Result<number, CicadaError>> {
    const cleanupResult = await this.deps.sessionService.cleanupExpiredSessions(timeoutMs);
    if (!cleanupResult.success) {
      return cleanupResult;
    }

    const count = cleanupResult.data;

    // TODO: Also disconnect devices for expired sessions
    // This would require extending the session entity to store deviceId

    return { success: true, data: count };
  }
}
