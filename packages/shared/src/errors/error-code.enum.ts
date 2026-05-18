export enum ErrorCode {
  AUTHENTICATION_ERROR = 'authentication_error',
  VALIDATION_ERROR = 'validation_error',
  DEVICE_OFFLINE = 'device_offline',
  DEVICE_NOT_FOUND = 'device_not_found',
  RATE_LIMIT_EXCEEDED = 'rate_limit_exceeded',
  SESSION_CONFLICT = 'session_conflict',
  SESSION_NOT_FOUND = 'session_not_found',
  COMMAND_NOT_FOUND = 'command_not_found',
  INVALID_STATE = 'invalid_state',
  SYSTEM_ERROR = 'system_error',
  TIMEOUT_ERROR = 'timeout_error',
  PROTOCOL_ERROR = 'protocol_error',
  WEBSOCKET_ERROR = 'websocket_error',
  UNKNOWN_ERROR = 'unknown_error',
}

