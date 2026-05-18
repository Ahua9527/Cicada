import type { Result } from '@cicada/shared/errors/result';
import { CicadaError, ErrorCode, ErrorSeverity } from '@cicada/shared/errors';
import type { SessionId, DeviceId } from '@cicada/shared/types/common.types';
import { Session } from '../../domain/session/session.entity';
import type { SessionRepository } from '../../domain/session/session.repository';

export interface SessionServiceDeps {
  sessionRepository: SessionRepository;
}

export class SessionService {
  constructor(private readonly deps: SessionServiceDeps) {}

  async createSession(
    deviceId: DeviceId,
    metadata?: Record<string, unknown>
  ): Promise<Result<Session, CicadaError>> {
    try {
      // Check if session already exists
      const existingResult = await this.deps.sessionRepository.findActiveByDeviceId(deviceId);
      if (existingResult.success && existingResult.data) {
        const existing = existingResult.data;
        if (existing.isActive) {
          return {
            success: false,
            error: new CicadaError(
              `Active session already exists for device ${deviceId}`,
              ErrorCode.SESSION_CONFLICT,
              { severity: ErrorSeverity.MEDIUM }
            ),
          };
        }
      }

      // Create new session
      const session = Session.create({
        deviceId,
        metadata: metadata as any,
      });

      // Save to repository
      const saveResult = await this.deps.sessionRepository.save(session);
      if (!saveResult.success) {
        return saveResult;
      }

      return { success: true, data: session };
    } catch (error) {
      return {
        success: false,
        error: new CicadaError('Failed to create session', ErrorCode.SYSTEM_ERROR, {
          severity: ErrorSeverity.HIGH,
          cause: error instanceof Error ? error : undefined,
        }),
      };
    }
  }

  async getSession(sessionId: SessionId): Promise<Result<Session | null, CicadaError>> {
    return this.deps.sessionRepository.findById(sessionId);
  }

  async getActiveSessionByDevice(
    deviceId: DeviceId
  ): Promise<Result<Session | null, CicadaError>> {
    const result = await this.deps.sessionRepository.findActiveByDeviceId(deviceId);
    if (!result.success) {
      return result;
    }

    const session = result.data;
    if (!session || !session.isActive) {
      return { success: true, data: null };
    }

    return { success: true, data: session };
  }

  async updateActivity(
    sessionId: SessionId,
    timestamp?: number
  ): Promise<Result<Session, CicadaError>> {
    const getResult = await this.deps.sessionRepository.findById(sessionId);
    if (!getResult.success) {
      return getResult;
    }

    const session = getResult.data;
    if (!session) {
      return {
        success: false,
        error: new CicadaError(`Session ${sessionId} not found`, ErrorCode.SESSION_NOT_FOUND, {
          severity: ErrorSeverity.MEDIUM,
        }),
      };
    }

    session.updateActivity(timestamp);

    const saveResult = await this.deps.sessionRepository.save(session);
    if (!saveResult.success) {
      return saveResult;
    }

    return { success: true, data: session };
  }

  async recordMessage(sessionId: SessionId): Promise<Result<void, CicadaError>> {
    const getResult = await this.deps.sessionRepository.findById(sessionId);
    if (!getResult.success) {
      return { success: false, error: getResult.error };
    }

    const session = getResult.data;
    if (!session) {
      return {
        success: false,
        error: new CicadaError(`Session ${sessionId} not found`, ErrorCode.SESSION_NOT_FOUND, {
          severity: ErrorSeverity.MEDIUM,
        }),
      };
    }

    session.recordMessage();

    const saveResult = await this.deps.sessionRepository.save(session);
    if (!saveResult.success) {
      return { success: false, error: saveResult.error };
    }

    return { success: true, data: undefined };
  }

  async closeSession(sessionId: SessionId): Promise<Result<void, CicadaError>> {
    const getResult = await this.deps.sessionRepository.findById(sessionId);
    if (!getResult.success) {
      return { success: false, error: getResult.error };
    }

    const session = getResult.data;
    if (!session) {
      return {
        success: false,
        error: new CicadaError(`Session ${sessionId} not found`, ErrorCode.SESSION_NOT_FOUND, {
          severity: ErrorSeverity.MEDIUM,
        }),
      };
    }

    session.markInactive();

    const saveResult = await this.deps.sessionRepository.save(session);
    if (!saveResult.success) {
      return { success: false, error: saveResult.error };
    }

    return { success: true, data: undefined };
  }

  async cleanupExpiredSessions(timeoutMs: number): Promise<Result<number, CicadaError>> {
    const listResult = await this.deps.sessionRepository.listActive();
    if (!listResult.success) {
      return { success: false, error: listResult.error };
    }

    const sessions = listResult.data;
    let cleaned = 0;

    for (const session of sessions) {
      if (session.hasTimedOut(timeoutMs)) {
        session.markInactive();
        const saveResult = await this.deps.sessionRepository.save(session);
        if (saveResult.success) {
          cleaned++;
        }
      }
    }

    return { success: true, data: cleaned };
  }
}
