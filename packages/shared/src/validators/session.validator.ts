import type { SessionInfo } from '../types/session.types';
import { BaseValidator } from './base.validator';

export class SessionValidator extends BaseValidator<SessionInfo> {
  validate(payload: SessionInfo): boolean {
    this.clear();

    if (payload.sessionId && payload.sessionId.length < 8) {
      this.addError('sessionId must be at least 8 characters when present');
    }

    if (payload.createdAt != null && payload.createdAt < 0) {
      this.addError('createdAt must be a positive timestamp');
    }

    if (payload.lastActivity != null && payload.lastActivity < 0) {
      this.addError('lastActivity must be a positive timestamp');
    }

    if (payload.connectedAt != null && payload.connectedAt < 0) {
      this.addError('connectedAt must be a positive timestamp');
    }

    if (payload.lastPing != null && payload.lastPing < 0) {
      this.addError('lastPing must be a positive timestamp');
    }

    return this.errors.length === 0;
  }
}

