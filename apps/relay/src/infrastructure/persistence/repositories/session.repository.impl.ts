/**
 * Session Repository Implementation
 * Implements SessionRepository using Durable Objects storage
 */

import {
  Session,
  DeviceId,
  SessionState,
  type SessionMetadata,
} from '../../../domain/session/session.entity';
import {
  RepositoryError,
  type SessionRepository,
  type SessionResult,
} from '../../../domain/session/session.repository';
import type { SessionId, DeviceId as DeviceIdentifier } from '@cicada/shared/types/common.types';
import type { SessionInfo } from '@cicada/shared/types/session.types';

export class SessionRepositoryImpl implements SessionRepository {
  constructor(private storage: any) {}

  async findById(sessionId: SessionId): Promise<SessionResult<Session | null>> {
    try {
      const sessionData = await this.storage.get(`session:${sessionId}`);

      if (!sessionData) {
        return { success: true, data: null };
      }

      const session = this.toEntity(sessionData);
      return { success: true, data: session };
    } catch (error) {
      return {
        success: false,
        error: this.toRepositoryError('Failed to find session', error, { sessionId }),
      };
    }
  }

  async save(session: Session): Promise<SessionResult<void>> {
    try {
      const sessionId = session.id;
      if (!sessionId) {
        return {
          success: false,
          error: new RepositoryError('Session ID is required to persist session', {
            deviceId: session.deviceId,
          }),
        };
      }

      const sessionInfo = this.toSessionInfo(session);
      await this.storage.put(`session:${sessionId}`, sessionInfo);
      return { success: true, data: undefined };
    } catch (error) {
      return {
        success: false,
        error: this.toRepositoryError('Failed to save session', error, {
          sessionId: session.id ?? null,
          deviceId: session.deviceId,
        }),
      };
    }
  }

  async delete(sessionId: SessionId): Promise<SessionResult<void>> {
    try {
      await this.storage.delete(`session:${sessionId}`);
      return { success: true, data: undefined };
    } catch (error) {
      return {
        success: false,
        error: this.toRepositoryError('Failed to delete session', error, { sessionId }),
      };
    }
  }

  async findActiveByDeviceId(
    deviceId: DeviceIdentifier | DeviceId
  ): Promise<SessionResult<Session | null>> {
    try {
      const allSessions = await this.storage.list({ prefix: 'session:' });

      for (const [, sessionData] of allSessions) {
        if (sessionData.deviceId === deviceId && sessionData.isActive) {
          const session = this.toEntity(sessionData);
          return { success: true, data: session };
        }
      }

      return { success: true, data: null };
    } catch (error) {
      return {
        success: false,
        error: this.toRepositoryError('Failed to find session by device ID', error, {
          deviceId,
        }),
      };
    }
  }

  async listActive(): Promise<SessionResult<Session[]>> {
    try {
      const allSessions = await this.storage.list({ prefix: 'session:' });
      const sessions: Session[] = [];

      for (const [, sessionData] of allSessions) {
        if (sessionData.isActive) {
          sessions.push(this.toEntity(sessionData));
        }
      }

      return { success: true, data: sessions };
    } catch (error) {
      return {
        success: false,
        error: this.toRepositoryError('Failed to list active sessions', error),
      };
    }
  }

  private toEntity(sessionInfo: SessionInfo): Session {
    const rawDeviceId = sessionInfo.deviceId;
    if (!rawDeviceId) {
      throw new RepositoryError('Session payload missing deviceId', {
        sessionId: sessionInfo.sessionId,
      });
    }

    const deviceId = DeviceId.create(rawDeviceId);
    if (!deviceId) {
      throw new RepositoryError('Stored session has invalid deviceId', {
        deviceId: rawDeviceId,
        sessionId: sessionInfo.sessionId,
      });
    }

    const metadata = sessionInfo.metadata as SessionMetadata | undefined;

    return Session.create({
      sessionId: sessionInfo.sessionId,
      deviceId,
      connectedAt: sessionInfo.connectedAt ?? undefined,
      lastActivity: sessionInfo.lastActivity ?? undefined,
      lastPing: sessionInfo.lastPing ?? null,
      metadata,
      state: sessionInfo.isActive ? SessionState.ACTIVE : SessionState.INACTIVE,
    });
  }

  private toSessionInfo(session: Session): SessionInfo {
    return session.toSessionInfo();
  }

  private toRepositoryError(
    message: string,
    cause: unknown,
    context?: Record<string, unknown>
  ): RepositoryError {
    return new RepositoryError(message, {
      ...context,
      cause: cause instanceof Error ? cause.message : String(cause),
    });
  }
}
