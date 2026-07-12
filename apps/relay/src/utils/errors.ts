/**
 * 错误处理工具
 *
 * 提供统一的错误类型和处理机制
 */

import { ErrorType, ApiResponse } from '../types';
import { Logger } from './logger';

/**
 * 基础应用错误类
 */
export abstract class AppError extends Error {
  public readonly type: ErrorType;
  public readonly statusCode: number;
  public readonly isOperational: boolean;
  public readonly context?: Record<string, unknown>;
  public readonly requestId?: string;

  constructor(
    message: string,
    type: ErrorType,
    statusCode: number = 500,
    isOperational: boolean = true,
    context?: Record<string, unknown>,
    requestId?: string
  ) {
    super(message);

    this.name = this.constructor.name;
    this.type = type;
    this.statusCode = statusCode;
    this.isOperational = isOperational;
    this.context = context;
    this.requestId = requestId;

    // 确保错误堆栈正确
    const captureStackTrace = (
      Error as ErrorConstructor & {
        captureStackTrace?: (targetObject: object) => void;
      }
    ).captureStackTrace;
    captureStackTrace?.(this);
  }

  /**
   * 转换为API响应格式
   */
  toApiResponse(): ApiResponse {
    return {
      ok: false,
      error: this.message,
      ...(this.context && { details: this.context }),
      ...(this.requestId && { request_id: this.requestId }),
    };
  }

  /**
   * 获取错误的详细信息（用于日志）
   */
  getDetails(): Record<string, unknown> {
    return {
      name: this.name,
      message: this.message,
      type: this.type,
      statusCode: this.statusCode,
      isOperational: this.isOperational,
      context: this.context,
      requestId: this.requestId,
      stack: this.stack,
    };
  }
}

/**
 * 认证错误
 */
export class AuthenticationError extends AppError {
  constructor(message: string = '认证失败', context?: Record<string, unknown>, requestId?: string) {
    super(message, ErrorType.AUTHENTICATION_ERROR, 401, true, context, requestId);
  }
}

/**
 * 验证错误
 */
export class ValidationError extends AppError {
  constructor(
    message: string = '请求参数验证失败',
    context?: Record<string, unknown>,
    requestId?: string
  ) {
    super(message, ErrorType.VALIDATION_ERROR, 400, true, context, requestId);
  }
}

/**
 * 设备离线错误
 */
export class DeviceOfflineError extends AppError {
  constructor(deviceId: string, context?: Record<string, unknown>, requestId?: string) {
    super(
      `设备 ${deviceId} 未连接`,
      ErrorType.DEVICE_OFFLINE,
      503,
      true,
      { deviceId, ...context },
      requestId
    );
  }
}

/**
 * 限流错误
 */
export class RateLimitError extends AppError {
  constructor(
    message: string = '请求频率超限',
    context?: Record<string, unknown>,
    requestId?: string
  ) {
    super(message, ErrorType.RATE_LIMIT_EXCEEDED, 429, true, context, requestId);
  }
}

/**
 * 系统错误
 */
export class SystemError extends AppError {
  constructor(
    message: string = '系统内部错误',
    originalError?: Error,
    context?: Record<string, unknown>,
    requestId?: string
  ) {
    super(
      message,
      ErrorType.SYSTEM_ERROR,
      500,
      false,
      { originalError: originalError?.message, ...context },
      requestId
    );
  }
}

/**
 * 超时错误
 */
export class TimeoutError extends AppError {
  constructor(
    operation: string,
    timeout: number,
    context?: Record<string, unknown>,
    requestId?: string
  ) {
    super(
      `${operation} 操作超时 (${timeout}ms)`,
      ErrorType.TIMEOUT_ERROR,
      408,
      true,
      { operation, timeout, ...context },
      requestId
    );
  }
}

/**
 * 协议错误
 */
export class ProtocolError extends AppError {
  constructor(message: string = '协议错误', context?: Record<string, unknown>, requestId?: string) {
    super(message, ErrorType.PROTOCOL_ERROR, 400, true, context, requestId);
  }
}

/**
 * WebSocket错误
 */
export class WebSocketError extends AppError {
  constructor(
    message: string = 'WebSocket连接错误',
    context?: Record<string, unknown>,
    requestId?: string
  ) {
    super(message, ErrorType.WEBSOCKET_ERROR, 500, true, context, requestId);
  }
}

/**
 * 错误工厂类
 */
export class ErrorFactory {
  /**
   * 从错误类型创建错误实例
   */
  static create(
    type: ErrorType,
    message?: string,
    context?: Record<string, unknown>,
    requestId?: string
  ): AppError {
    switch (type) {
      case ErrorType.AUTHENTICATION_ERROR:
        return new AuthenticationError(message, context, requestId);
      case ErrorType.VALIDATION_ERROR:
        return new ValidationError(message, context, requestId);
      case ErrorType.DEVICE_OFFLINE:
        return new DeviceOfflineError(
          (context?.deviceId as string | undefined) ?? 'unknown',
          context,
          requestId
        );
      case ErrorType.RATE_LIMIT_EXCEEDED:
        return new RateLimitError(message, context, requestId);
      case ErrorType.TIMEOUT_ERROR:
        return new TimeoutError(
          (context?.operation as string | undefined) ?? 'unknown',
          (context?.timeout as number | undefined) ?? 30000,
          context,
          requestId
        );
      case ErrorType.PROTOCOL_ERROR:
        return new ProtocolError(message, context, requestId);
      case ErrorType.WEBSOCKET_ERROR:
        return new WebSocketError(message, context, requestId);
      case ErrorType.SYSTEM_ERROR:
      default:
        return new SystemError(message, undefined, context, requestId);
    }
  }

  /**
   * 从原生错误创建应用错误
   */
  static fromNativeError(
    error: Error,
    defaultMessage?: string,
    context?: Record<string, unknown>,
    requestId?: string
  ): AppError {
    // 如果已经是应用错误，直接返回
    if (error instanceof AppError) {
      return error;
    }

    // 根据错误类型判断
    if (error.name === 'ValidationError') {
      return new ValidationError(error.message, context, requestId);
    }

    if (error.name === 'TimeoutError') {
      return new TimeoutError(
        '操作',
        30000,
        { originalError: error.message, ...context },
        requestId
      );
    }

    // 默认为系统错误，使用原始错误消息
    const message = error.message ?? defaultMessage ?? '未知错误';
    return new SystemError(message, error, context, requestId);
  }
}

/**
 * 错误处理器类
 */
export class ErrorHandler {
  constructor(private logger: Logger) {}

  /**
   * 处理错误并返回API响应
   */
  handleError(error: unknown, requestId?: string, context?: Record<string, unknown>): ApiResponse {
    let appError: AppError;

    if (error instanceof AppError) {
      appError = error;
    } else if (error instanceof Error) {
      appError = ErrorFactory.fromNativeError(error, '处理请求时发生错误', context, requestId);
    } else {
      appError = new SystemError(String(error), undefined, context, requestId);
    }

    // 记录错误日志
    this.logger.error('Error occurred', {
      requestId,
      error: appError,
      tags: ['error', appError.type.toUpperCase()],
    });

    // 返回API响应
    return appError.toApiResponse();
  }

  /**
   * 异步处理错误
   */
  async handleAsyncError<T>(
    asyncFn: () => Promise<T>,
    requestId?: string,
    context?: Record<string, unknown>
  ): Promise<{ success: true; data: T } | { success: false; error: ApiResponse }> {
    try {
      const data = await asyncFn();
      return { success: true, data };
    } catch (error) {
      const apiResponse = this.handleError(error, requestId, context);
      return { success: false, error: apiResponse };
    }
  }

  /**
   * 包装异步函数以捕获错误
   */
  wrapAsync<T extends (...args: unknown[]) => Promise<unknown>>(fn: T, requestId?: string): T {
    return (async (...args: Parameters<T>) => {
      try {
        return await fn(...args);
      } catch (error) {
        const apiResponse = this.handleError(error, requestId, { functionName: fn.name });
        throw apiResponse;
      }
    }) as T;
  }

}

/**
 * 全局错误处理器实例
 */
export const globalErrorHandler = new ErrorHandler(
  // 注意：这里使用循环依赖，实际使用时需要从外部注入logger
  // 或者延迟初始化
  new Logger() as Logger
);

/**
 * 便捷的错误处理函数
 */
export function handleError(
  error: unknown,
  requestId?: string,
  context?: Record<string, unknown>
): ApiResponse {
  return globalErrorHandler.handleError(error, requestId, context);
}

/**
 * 便捷的异步错误处理函数
 */
export async function handleAsyncError<T>(
  asyncFn: () => Promise<T>,
  requestId?: string,
  context?: Record<string, unknown>
): Promise<{ success: true; data: T } | { success: false; error: ApiResponse }> {
  return globalErrorHandler.handleAsyncError(asyncFn, requestId, context);
}

/**
 * 检查错误是否为可重试的错误
 */
export function isRetryableError(error: AppError): boolean {
  // 系统错误和超时错误通常可以重试
  return (
    error.type === ErrorType.SYSTEM_ERROR ||
    error.type === ErrorType.TIMEOUT_ERROR ||
    error.type === ErrorType.DEVICE_OFFLINE
  );
}

/**
 * 计算错误重试延迟
 */
export function calculateRetryDelay(attempt: number, baseDelay: number = 1000): number {
  // 指数退避算法，加上随机抖动
  const exponentialDelay = baseDelay * Math.pow(2, attempt);
  const jitter = Math.random() * 0.1 * exponentialDelay;
  return Math.min(exponentialDelay + jitter, 30000); // 最大30秒
}
