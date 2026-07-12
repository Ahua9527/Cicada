/**
 * 错误处理单元测试
 */

import {
  AppError,
  AuthenticationError,
  ValidationError,
  DeviceOfflineError,
  RateLimitError,
  SystemError,
  TimeoutError,
  ProtocolError,
  WebSocketError,
  ErrorFactory,
  ErrorHandler,
  handleError,
  handleAsyncError,
  isRetryableError,
  calculateRetryDelay,
} from '../../src/utils/errors';
import { Logger } from '../../src/utils/logger';
import { ErrorType } from '../../src/types';

class ConcreteAppError extends AppError {
  constructor(
    message: string,
    type: ErrorType,
    statusCode?: number,
    isOperational?: boolean,
    context?: Record<string, any>,
    requestId?: string
  ) {
    super(message, type, statusCode, isOperational, context, requestId);
  }
}

describe('Error Classes', () => {
  describe('AuthenticationError', () => {
    it('should create authentication error with default message', () => {
      const error = new AuthenticationError();

      expect(error).toBeInstanceOf(AppError);
      expect(error.name).toBe('AuthenticationError');
      expect(error.message).toBe('认证失败');
      expect(error.type).toBe(ErrorType.AUTHENTICATION_ERROR);
      expect(error.statusCode).toBe(401);
      expect(error.isOperational).toBe(true);
    });

    it('should create authentication error with custom message', () => {
      const error = new AuthenticationError('Custom auth error');

      expect(error.message).toBe('Custom auth error');
    });
  });

  describe('ValidationError', () => {
    it('should create validation error', () => {
      const error = new ValidationError('Invalid input');

      expect(error).toBeInstanceOf(AppError);
      expect(error.type).toBe(ErrorType.VALIDATION_ERROR);
      expect(error.statusCode).toBe(400);
    });
  });

  describe('DeviceOfflineError', () => {
    it('should create device offline error', () => {
      const error = new DeviceOfflineError('device-123');

      expect(error.type).toBe(ErrorType.DEVICE_OFFLINE);
      expect(error.statusCode).toBe(503);
      expect(error.context?.deviceId).toBe('device-123');
    });
  });

  describe('RateLimitError', () => {
    it('should create rate limit error', () => {
      const error = new RateLimitError('Too many requests');

      expect(error.type).toBe(ErrorType.RATE_LIMIT_EXCEEDED);
      expect(error.statusCode).toBe(429);
    });
  });

  describe('SystemError', () => {
    it('should create system error', () => {
      const originalError = new Error('Original error');
      const error = new SystemError('System failed', originalError);

      expect(error.type).toBe(ErrorType.SYSTEM_ERROR);
      expect(error.statusCode).toBe(500);
      expect(error.isOperational).toBe(false);
      expect(error.context?.originalError).toBe('Original error');
    });
  });

  describe('TimeoutError', () => {
    it('should create timeout error', () => {
      const error = new TimeoutError('database query', 5000);

      expect(error.type).toBe(ErrorType.TIMEOUT_ERROR);
      expect(error.statusCode).toBe(408);
      expect(error.context?.operation).toBe('database query');
      expect(error.context?.timeout).toBe(5000);
    });
  });

  it('creates protocol and WebSocket errors with their public defaults', () => {
    const protocolError = new ProtocolError();
    const webSocketError = new WebSocketError();

    expect(protocolError).toMatchObject({
      message: '协议错误',
      type: ErrorType.PROTOCOL_ERROR,
      statusCode: 400,
    });
    expect(webSocketError).toMatchObject({
      message: 'WebSocket连接错误',
      type: ErrorType.WEBSOCKET_ERROR,
      statusCode: 500,
    });
  });
});

describe('ErrorFactory', () => {
  it('should create authentication error', () => {
    const error = ErrorFactory.create(ErrorType.AUTHENTICATION_ERROR, 'Auth failed');

    expect(error).toBeInstanceOf(AuthenticationError);
    expect(error.message).toBe('Auth failed');
  });

  it('should create validation error', () => {
    const error = ErrorFactory.create(ErrorType.VALIDATION_ERROR, 'Invalid data');

    expect(error).toBeInstanceOf(ValidationError);
  });

  it('should create device offline error with device ID', () => {
    const error = ErrorFactory.create(ErrorType.DEVICE_OFFLINE, '', {
      deviceId: 'device-123',
    });

    expect(error).toBeInstanceOf(DeviceOfflineError);
    expect(error.message).toContain('device-123');
  });

  it('should create system error for unknown type', () => {
    const error = ErrorFactory.create('unknown' as ErrorType, 'Unknown error');

    expect(error).toBeInstanceOf(SystemError);
  });

  it.each([
    [ErrorType.RATE_LIMIT_EXCEEDED, RateLimitError],
    [ErrorType.PROTOCOL_ERROR, ProtocolError],
    [ErrorType.WEBSOCKET_ERROR, WebSocketError],
    [ErrorType.SYSTEM_ERROR, SystemError],
  ])('creates the expected error for %s', (type, expectedClass) => {
    const error = ErrorFactory.create(type, 'custom', { field: 'value' }, 'req-factory');

    expect(error).toBeInstanceOf(expectedClass);
    expect(error.requestId).toBe('req-factory');
  });

  it('creates timeout defaults when context is omitted', () => {
    const error = ErrorFactory.create(ErrorType.TIMEOUT_ERROR);

    expect(error).toBeInstanceOf(TimeoutError);
    expect(error.context).toMatchObject({ operation: 'unknown', timeout: 30000 });
  });

  it('creates an unknown-device error when context is omitted', () => {
    const error = ErrorFactory.create(ErrorType.DEVICE_OFFLINE);

    expect(error).toBeInstanceOf(DeviceOfflineError);
    expect(error.message).toContain('unknown');
  });

  it.each([
    ['ValidationError', ValidationError],
    ['TimeoutError', TimeoutError],
  ])('maps native %s names', (name, expectedClass) => {
    const nativeError = new Error('native details');
    nativeError.name = name;

    const result = ErrorFactory.fromNativeError(nativeError, undefined, { operation: 'test' }, 'req-native');

    expect(result).toBeInstanceOf(expectedClass);
    expect(result.requestId).toBe('req-native');
  });

  it('should convert native error to application error', () => {
    const nativeError = new Error('Native error');
    const appError = ErrorFactory.fromNativeError(nativeError, 'Failed to process');

    expect(appError).toBeInstanceOf(AppError);
    expect(appError.message).toBe('Native error');
  });

  it('should return existing application error unchanged', () => {
    const originalError = new ValidationError('Validation failed');
    const result = ErrorFactory.fromNativeError(originalError);

    expect(result).toBe(originalError);
  });
});

describe('ErrorHandler', () => {
  let mockLogger: jest.Mocked<Logger>;
  let errorHandler: ErrorHandler;

  beforeEach(() => {
    mockLogger = {
      error: jest.fn(),
      warn: jest.fn(),
      info: jest.fn(),
      debug: jest.fn(),
    } as any;

    errorHandler = new ErrorHandler(mockLogger);
  });

  it('should handle application error', () => {
    const error = new ValidationError('Invalid input');
    const result = errorHandler.handleError(error, 'req-123');

    expect(result).toEqual({
      ok: false,
      error: 'Invalid input',
    });

    expect(mockLogger.error).toHaveBeenCalledWith(
      'Error occurred',
      expect.objectContaining({
        requestId: 'req-123',
        error,
        tags: ['error', 'VALIDATION_ERROR'],
      })
    );
  });

  it('should handle native error', () => {
    const error = new Error('Native error');
    const result = errorHandler.handleError(error, 'req-123');

    expect(result.ok).toBe(false);
    expect(result.error).toBe('Native error');

    expect(mockLogger.error).toHaveBeenCalled();
  });

  it('should handle string error', () => {
    const error = 'String error message';
    const result = errorHandler.handleError(error, 'req-123');

    expect(result.ok).toBe(false);
    expect(result.error).toBe('String error message');
  });

  it('should handle async operation successfully', async () => {
    const asyncFn = jest.fn().mockResolvedValue('success');
    const result = await errorHandler.handleAsyncError(asyncFn, 'req-123');

    expect(result).toEqual({
      success: true,
      data: 'success',
    });
  });

  it('should handle async operation error', async () => {
    const asyncFn = jest.fn().mockRejectedValue(new Error('Async error'));
    const result = await errorHandler.handleAsyncError(asyncFn, 'req-123');

    if (result.success) {
      throw new Error('Expected async error to be handled as failure');
    }

    expect(result.error.ok).toBe(false);
    expect(mockLogger.error).toHaveBeenCalled();
  });

  it('should wrap and invoke an async function', async () => {
    const originalFn = jest.fn(async (value: unknown) => value);
    const wrappedFn = errorHandler.wrapAsync(originalFn, 'req-123');

    await expect(wrappedFn('success')).resolves.toBe('success');
    expect(originalFn).toHaveBeenCalledWith('success');
  });

  it('should throw the API response when a wrapped function fails', async () => {
    const originalFn = jest.fn(async () => {
      throw new ValidationError('bad argument');
    });
    const wrappedFn = errorHandler.wrapAsync(originalFn, 'req-123');

    await expect(wrappedFn()).rejects.toEqual({ ok: false, error: 'bad argument' });
    expect(mockLogger.error).toHaveBeenCalledWith(
      'Error occurred',
      expect.objectContaining({ requestId: 'req-123' })
    );
  });
});

describe('Global error helpers', () => {
  it('handles a global synchronous error', () => {
    expect(handleError(new ValidationError('invalid'), 'req-global')).toEqual({
      ok: false,
      error: 'invalid',
    });
  });

  it('handles successful and failed global async operations', async () => {
    await expect(handleAsyncError(async () => 'ok')).resolves.toEqual({
      success: true,
      data: 'ok',
    });
    await expect(
      handleAsyncError(async () => {
        throw new ValidationError('invalid');
      })
    ).resolves.toEqual({ success: false, error: { ok: false, error: 'invalid' } });
  });
});

describe('Utility Functions', () => {
  describe('isRetryableError', () => {
    it('should identify system errors as retryable', () => {
      const error = new SystemError('System failure');
      expect(isRetryableError(error)).toBe(true);
    });

    it('should identify timeout errors as retryable', () => {
      const error = new TimeoutError('operation', 5000);
      expect(isRetryableError(error)).toBe(true);
    });

    it('should identify device offline errors as retryable', () => {
      const error = new DeviceOfflineError('device-123');
      expect(isRetryableError(error)).toBe(true);
    });

    it('should not identify validation errors as retryable', () => {
      const error = new ValidationError('Invalid input');
      expect(isRetryableError(error)).toBe(false);
    });

    it('should not identify authentication errors as retryable', () => {
      const error = new AuthenticationError('Auth failed');
      expect(isRetryableError(error)).toBe(false);
    });
  });

  describe('calculateRetryDelay', () => {
    it('should calculate exponential backoff', () => {
      const delay1 = calculateRetryDelay(0);
      const delay2 = calculateRetryDelay(1);
      const delay3 = calculateRetryDelay(2);

      expect(delay2).toBeGreaterThan(delay1);
      expect(delay3).toBeGreaterThan(delay2);
    });

    it('should use custom base delay', () => {
      const delay = calculateRetryDelay(1, 2000);
      expect(delay).toBeGreaterThanOrEqual(2000);
      expect(delay).toBeLessThan(2000 * 2.2); // Allow for jitter
    });

    it('should cap maximum delay', () => {
      const delay = calculateRetryDelay(10); // Should be capped at 30000ms
      expect(delay).toBeLessThanOrEqual(30000);
    });

    it('should include jitter', () => {
      // Run multiple times with same parameters
      const delays = Array.from({ length: 10 }, () => calculateRetryDelay(1));
      const uniqueDelays = [...new Set(delays)];

      // Should have some variation due to jitter
      expect(uniqueDelays.length).toBeGreaterThan(1);
    });
  });
});

describe('AppError Base Class', () => {
  it('should create error with all properties', () => {
    const context = { field: 'value' };
    const error = new ConcreteAppError(
      'Test error',
      ErrorType.SYSTEM_ERROR,
      500,
      true,
      context,
      'req-123'
    );

    expect(error.message).toBe('Test error');
    expect(error.type).toBe(ErrorType.SYSTEM_ERROR);
    expect(error.statusCode).toBe(500);
    expect(error.isOperational).toBe(true);
    expect(error.context).toEqual(context);
    expect(error.requestId).toBe('req-123');
    expect(error.name).toBe('ConcreteAppError');
    expect(error.stack).toBeDefined();
  });

  it('should convert to API response', () => {
    const error = new ConcreteAppError(
      'Test error',
      ErrorType.VALIDATION_ERROR,
      400,
      true,
      { field: 'value' },
      'req-123'
    );

    const response = error.toApiResponse();

    expect(response).toEqual({
      ok: false,
      error: 'Test error',
      details: { field: 'value' },
      request_id: 'req-123',
    });
  });

  it('omits optional API response fields when absent', () => {
    const error = new ConcreteAppError('Test error', ErrorType.SYSTEM_ERROR);

    expect(error.toApiResponse()).toEqual({ ok: false, error: 'Test error' });
  });

  it('should get error details', () => {
    const error = new ConcreteAppError(
      'Test error',
      ErrorType.SYSTEM_ERROR,
      500,
      false,
      { context: 'value' },
      'req-123'
    );

    const details = error.getDetails();

    expect(details).toEqual({
      name: 'ConcreteAppError',
      message: 'Test error',
      type: ErrorType.SYSTEM_ERROR,
      statusCode: 500,
      isOperational: false,
      context: { context: 'value' },
      requestId: 'req-123',
      stack: expect.any(String),
    });
  });
});
