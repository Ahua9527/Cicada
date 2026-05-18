import type { ApiResponse, JsonValue } from '../types/common.types';
import { ErrorCode } from './error-code.enum';
import { ErrorSeverity } from './error-severity.enum';

export interface CicadaErrorOptions {
  statusCode?: number;
  severity?: ErrorSeverity;
  context?: Record<string, JsonValue>;
  requestId?: string;
  cause?: unknown;
}

export class CicadaError extends Error {
  public readonly code: ErrorCode;
  public readonly statusCode: number;
  public readonly severity: ErrorSeverity;
  public readonly context: Record<string, JsonValue> | undefined;
  public readonly requestId: string | undefined;

  constructor(message: string, code: ErrorCode, options: CicadaErrorOptions = {}) {
    super(message);
    this.name = 'CicadaError';
    this.code = code;
    this.statusCode = options.statusCode ?? 500;
    this.severity = options.severity ?? ErrorSeverity.MEDIUM;
    this.context = options.context;
    this.requestId = options.requestId;

    if (options.cause && (this as { cause?: unknown }).cause === undefined) {
      (this as { cause?: unknown }).cause = options.cause;
    }
  }

  toApiResponse<T = unknown>(): ApiResponse<T> {
    const response: ApiResponse<T> = {
      ok: false,
      error: this.message,
      message: this.message,
      timestamp: Date.now(),
    };

    if (this.requestId) {
      response.requestId = this.requestId;
    }

    if (this.context) {
      response.data = this.context as unknown as T;
    }

    return response;
  }

  toJSON(): Record<string, JsonValue> {
    const payload: Record<string, JsonValue> = {
      name: this.name,
      message: this.message,
      code: this.code,
      severity: this.severity,
      statusCode: this.statusCode,
    };

    if (this.requestId) {
      payload.requestId = this.requestId;
    }

    if (this.context) {
      payload.context = this.context;
    }

    if (this.stack) {
      payload.stack = this.stack;
    }

    return payload;
  }
}
