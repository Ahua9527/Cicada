import type { Result } from '@cicada/shared/errors';
import { ErrorCode, ErrorSeverity, CicadaError } from '@cicada/shared/errors';
import type {
  JsonValue,
  SessionId,
  DeviceId as DeviceIdString,
} from '@cicada/shared/types/common.types';
import { DeviceId, Session } from './session.entity';

export class RepositoryError extends CicadaError {
  constructor(message: string, context?: Record<string, JsonValue>) {
    super(message, ErrorCode.SYSTEM_ERROR, { severity: ErrorSeverity.HIGH, context });
    this.name = 'RepositoryError';
  }
}

export type SessionResult<T> = Result<T, RepositoryError>;

export interface SessionRepository {
  findById(sessionId: SessionId): Promise<SessionResult<Session | null>>;
  findActiveByDeviceId(deviceId: DeviceId | DeviceIdString): Promise<SessionResult<Session | null>>;
  listActive(): Promise<SessionResult<Session[]>>;
  save(session: Session): Promise<SessionResult<void>>;
  delete(sessionId: SessionId): Promise<SessionResult<void>>;
}
