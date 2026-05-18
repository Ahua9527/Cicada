import { Result } from '@cicada/shared/errors';
import { ErrorCode, ErrorSeverity, CicadaError } from '@cicada/shared/errors';
import type { JsonValue } from '@cicada/shared/types/common.types';
import type { SessionInfo } from '@cicada/shared/types/session.types';
import { SessionValidator as SharedSessionValidator } from '@cicada/shared/validators';
import {
  DeviceId,
  DomainTimestamp,
  Session,
  SessionState,
  type SessionMetadata,
  type SessionProps,
} from './session.entity';

export type SessionValidationInput = {
  deviceId: string;
  sessionId?: string | null;
  ipAddress?: string;
  userAgent?: string;
  metadata?: Record<string, JsonValue>;
  connectedAt?: number;
  lastActivity?: number;
  lastPing?: number | null;
  totalMessages?: number;
  totalDurationMs?: number;
  timeoutCount?: number;
  cleanupRequested?: boolean;
  state?: SessionState;
};

export class SessionValidationError extends CicadaError {
  constructor(message: string, context?: Record<string, JsonValue>) {
    super(message, ErrorCode.VALIDATION_ERROR, { severity: ErrorSeverity.MEDIUM, context });
    this.name = 'SessionValidationError';
  }
}

export class SessionValidator {
  private readonly baseValidator = new SharedSessionValidator();

  validate(input: SessionValidationInput): Result<Session, SessionValidationError> {
    const deviceId = DeviceId.create(input.deviceId);
    if (!deviceId) {
      return Result.err(
        new SessionValidationError('Device ID must match MAC_[32 hex] format', {
          deviceId: input.deviceId,
        })
      );
    }

    if (input.sessionId != null && input.sessionId.trim() === '') {
      return Result.err(
        new SessionValidationError('Session ID cannot be empty', { sessionId: input.sessionId })
      );
    }

    const connectedAt = DomainTimestamp.create(input.connectedAt) ?? DomainTimestamp.now();
    const lastActivity = DomainTimestamp.create(input.lastActivity) ?? connectedAt;
    const lastPing = DomainTimestamp.create(input.lastPing ?? null);

    if (lastActivity.toNumber() < connectedAt.toNumber()) {
      return Result.err(
        new SessionValidationError('lastActivity cannot be before connectedAt', {
          connectedAt: connectedAt.toNumber(),
          lastActivity: lastActivity.toNumber(),
        })
      );
    }

    if (lastPing && lastPing.toNumber() < lastActivity.toNumber()) {
      return Result.err(
        new SessionValidationError('lastPing cannot be before lastActivity', {
          lastPing: lastPing.toNumber(),
          lastActivity: lastActivity.toNumber(),
        })
      );
    }

    const metadata: SessionMetadata = { ...(input.metadata ?? {}) };
    if (input.ipAddress) {
      metadata.ipAddress = input.ipAddress;
    }
    if (input.userAgent) {
      metadata.userAgent = input.userAgent;
    }

    const info: SessionInfo = {
      sessionId: input.sessionId ?? null,
      deviceId: deviceId.toString(),
      isActive: input.state ? input.state === SessionState.ACTIVE : true,
      createdAt: connectedAt.toNumber(),
      lastActivity: lastActivity.toNumber(),
      connectedAt: connectedAt.toNumber(),
      lastPing: lastPing?.toNumber(),
      metadata,
    };

    if (!this.baseValidator.validate(info)) {
      return Result.err(
        new SessionValidationError('Session payload failed validation', {
          errors: this.baseValidator.getErrors().join(', '),
        })
      );
    }

    const props: SessionProps = {
      sessionId: input.sessionId ?? null,
      deviceId,
      connectedAt: connectedAt.toNumber(),
      lastActivity: lastActivity.toNumber(),
      lastPing: lastPing?.toNumber() ?? null,
      metadata,
      totalMessages: input.totalMessages,
      totalDurationMs: input.totalDurationMs,
      timeoutCount: input.timeoutCount,
      cleanupRequested: input.cleanupRequested,
      state: input.state,
    };

    return Result.ok(Session.create(props)) as Result<Session, SessionValidationError>;
  }
}
